class Event < Riddl::Implementation

  def response
    pp "======================Event===================="
    ra    = JSON.parse(@p.value("notification"))
    data  = Store.instance.data
    unless ra['instance_uuid'].nil? then
      uuid = ra['instance_uuid']
      topic = (@p.value("topic").nil? ? "unknown" : @p.value("topic") )
      event = (@p.value("event").nil? ? "unknown" : @p.value("event") )

      case @h['RIDDL_DECLARATION_RESOURCE'].split('/').last
      when 'engine'
        #save instance state
        activity_id = ra['activity'].to_sym
        if data[uuid][activity_id][:engine][@p.value("topic").to_sym][@p.value("event").to_sym].empty? then
          doc = XML::Smart.string(do_request(ra['instance']+'/properties/',"get")[0].value.read)
          doc.register_namespace "s",'http://riddl.org/ns/common-patterns/properties/1.0'
          data[uuid][:info] =  doc.find("string(/s:properties/s:attributes/s:info)")
        end
        data[uuid][activity_id][:engine][@p.value("topic").to_sym][@p.value("event").to_sym] = ra
        check(data,[uuid,activity_id])
      when 'worklist'
        activity_id = ra['cpee_activity'].to_sym
        data[uuid][activity_id][:worklist][@p.value("topic").to_sym][@p.value("event").to_sym] = ra
        check(data,[uuid,activity_id])
      else 'robot'
        activity_id = ra['activity'].to_sym
        #only for Proof of concept
        ra.each do |k,v|
          if v.kind_of?(Array)
            pp 'is array'
            pp v
            #pp v[0]&.[]('message')&.[]('content')
            unless v[0]&.[]('message')&.[]('content').nil?
              v[0]['message']['content'].each{ |elem|
                data[uuid][activity_id][:robot][topic.to_sym][event.to_sym]['received']['message']['content'][elem['ID']] = elem
              }
            else
              data[uuid][activity_id][:robot][topic.to_sym][event.to_sym][k] = v
            end
          else
            data[uuid][activity_id][:robot][topic.to_sym][event.to_sym][k] = v
          end
        end
      end

      check(data,[uuid,activity_id])

      store = YAML::Store.new "resources/state_save.yml"
      store.transaction do
        #pp data
        store[:data] = data
      end
    end
  end
end

def check(data,current)
  rules        = Store.instance.rules
  match_cache  = Store.instance.match_cache
  #match = [ruleid,symbol,match position]
  match        = match_current(data,rules,current)

  pp "match"
  pp match
  unless match.nil? then
    #get only matched rules, TODO Problem? if id and proces info more then once!
    rule = rules.select{|r| (r['id'] == match[0]) }

    #check condition for matched rule (only one)
    check_condition(data,current,match,match_cache,rule)
    #check sequence
    check_structure(data,current,match,match_cache,rule)
  end
    pp "match cache"
    pp match_cache
end

def check_condition(data,current,match,match_cache,rules)
  rules.each{ |r|
    # filtering for symbol :a == :a
    # TODO have to do the parsing twice for c[0]
    app_conditions = r["condition"].select{|c| parse_path(c[0],0,3)[0] == match[1]}
    #make an entry for every condition into match_cache
    if match_cache[r['process']][match[0]][current[0]][match[1]][current[1]].empty? then
      (0..app_conditions.size-1).each{|count| match_cache[r['process']][match[0]][current[0]][match[1]][current[1]][count] = nil}
    end
    app_conditions.each_with_index{|ar,i|
      #TODO refactor? do the same with both ends of the rule ?!
      if is_reference?(ar.last) then

        symbo = parse_path(ar.last)[0]
        pp "parse_path"
        pp symbo
        pp "current"
        pp current
        pp "match_cache"
        pp match_cache
        newcurr = []
        newcurr.replace(current)
        if symbo != current[1] then
          pp "adapted current"
          newcurr[1]=match_cache[r['process']][match[0]][current[0]][symbo].keys[0]
        end
        cond = data.dig(*newcurr).dig(*parse_path(ar.last)[1..-1])
        pp "cond"
        pp cond
      else
        cond = ar.last
      end
      #from here if path
      path = parse_path(ar[0])[1..-1].map{|pa| pa = try_int(pa)}
      pp "current2"
      pp current
      pp "path"
      pp path
      search = data.dig(*current)
      pp search
      path.chunk{|p| p=='*'||p==:*}.each{|k,v|
        if k then
          product, bottom = {},[]
          search.values.each{ |v| v.is_a?(Hash) ? product = product.deep_merge(v) : product = product.deep_merge({'+'=>(bottom + [v]).flatten})}
          search = product
        else
          search = search.dig(*v)
        end
      }
      pp "lefthandside"
      pp search

      # from here if not / else

      unless search.nil? || search.empty? then
        #search = try_numerical(search)
        begin search.extend(ConditionMethods) rescue pp "cannot extend, shit is immediate" end
        passed =  search.send ar[1], try_numerical(cond)
        pp "#{search} #{ar[1]} #{cond}"
        pp "passed == #{passed}"
        match_cache[r['process']][match[0]][current[0]][match[1]][current[1]][i] = passed
      end
    }
  }
end



module ConditionMethods
  def to_time
    Time.at(self)
  end
  def day
    Time.at(self).day
  end
  def before(t2)
    if(t2.is_a?(Numeric) && self.is_a?(Numeric)) then
      Time.at(self) < Time.at(t2)
    end
  end
  def after(t2)
    Time.at(self) > Time.at(t2)
  end
  def withindays(days)
    t1 = Time.at(self).to_date
    t2 = Time.now.to_date
    t1.next_day(days) >= t2
  end
  def withinhours(hours)
    t1 = Time.at(self)
    t2 = Time.now
    (t1 + (60*60*hours)) <= t2
  end
  def avg(var)
    vars = Store.instance.vars
    value = try_numerical(self)
    pp "vars"
    pp vars
    if vars[var].nil? then
      vars[var] = value
      return true
    else
      pp "var"
      pp vars[var]
      pp value
      vars[var] = ((vars[var] + value)/2)
      pp "var"
      pp vars[var]
      if vars[var] * 1.2 < value || vars[var] * 0.8 > value then
        return false
      end
    end
    true
  end
end

def check_structure(data,current,match,match_cache,rules)
  pp match
  rules.each do |r|
    if match[2] == (r['match'].size)-1 then
      order = []
      (match[2]).downto(0).each_with_index{ |i|
        key= r['match'][i].keys[0]
        order << match_cache[r['process']][match[0]][current[0]][key].map{|activity,v| v.size == v.inject(0){|sum,(k,value)| value==false ? sum : sum+1}}[0]
      }
      pp order
      if order.size == r['match'].size
        if order.include?(false) then
          r['ifnot'].each{|a| do_action(a,current)}
        elsif
          r['if'].each{|a| do_action(a,current)}
        end
      end
    end
  end
end

def try_numerical(s)
  case s
  when /^\d+\/\d+$/
    return Rational(s)
  when /^[-+]?[0-9]*\.[0-9]+$/
    return Float(s)
  when /\A[-+]?\d+\z/
    return s.to_i
  else
    return s
  end
end

def try_int(s)
  case s
  when /\A[-+]?\d+\z/
    return s.to_i
  else
    return s
  end
end

#only match in instance and activity of current event
def match_current(data,rules,current)
      rules.each{ |r|
        #TODO in bereits erledigten nicht mehr schauen?
      #  if data[current[0]][:info] == r['process'] then
          r['match'].each_with_index{|mr,i|
            mr.each{|symbol,v|
              m = 0
              v.each{ |c|
                search = parse_path(c[0],0,2)
                if data.dig(*current).dig(*search).send c[1], c[2] then m += 1 else break end
              }
              #if matched  then return rule id (first that matched) and corresponding symbol
              if m == v.size then return [r['id'],symbol,i] end
            }
          }
      #  end
      }
      nil
end

#match in all instance
def match(data,rules)
  matches = Array.new
  data.each{|uuid,activity|
    activity.each{|a,ev|
      rules.each{ |r|
        r['match'].each_with_index{|mr,i|
          mr.each{|symbol,v|
            m = 0
            v.each{ |c|
              search = parse_path(c[0],0,2)
              if ev.dig(*search).send c[1], c[2] then m += 1 else break end
            }
            if m == v.size then matches << [r['id'],uuid,a,symbol,i] end
          }
        }
      }
    }
  }
  matches
end

def is_reference?(string)
  if string.is_a? String then
    string.split(/\s*>\s*/).size > 1 ?  true :  false
  else
    false
  end
end

def parse_path(string,m=0,n=3)
  s = string.split(/\s*>\s*/)
  s.size >= n ? s[m..n] = s[m..n].map{|d| d = d.to_sym} : s
  s
end

def do_request(uri,method, data={})
  uri              = URI(URI.escape(uri))
  srv              = Riddl::Client.new("#{uri.scheme}://#{uri.host}:#{uri.port}")
  params           = data.map{|k,v|Riddl::Parameter::Simple.new(k,v)}
  res              = srv.resource("#{uri.path}")
  status, response = res.send method, params
  response
end

def do_action(send_action,current)
  actions = Store.instance.actions
  data    = Store.instance.data
  actions.each{ |action|
    if action[0] == send_action.to_sym then
      begin
        url = action[1][:url].inject("") {|con,para| is_reference?(para) ? con += data.dig(*current).dig(*parse_path(para,0,2)) : con += para }
        pp url
        do_request(url,action[1][:method],action[1][:data].nil? ? {} : action[1][:data])
      rescue
        pp "action #{action[0]} did not work"
      end
    end
  }
end

class Store
  include Singleton
  attr_accessor :data, :rules, :match_cache, :actions, :vars
  def initialize
    #TODO yml store as extensible hash, all data to store?
    @match_cache = Hash.new
    store = YAML::Store.new "resources/state_save.yml"
    def_proc = Proc.new {|hash, key| hash[key] = Hash.new(&hash.default_proc) }
    store.transaction{@data = store[:data]}
    @data ||= {}
    @data.default_proc = @match_cache.default_proc = def_proc
    @vars = Hash.new
    @rules   = load_rules
    @actions = load_actions
  end

  def load_rules
    rules= []
    Dir.glob(File.dirname(__FILE__) + '/' + '../rules/*.yml') do |yml_file|
      rules << YAML.load_file(yml_file)
    end
    rules.sort{ |r| r['id'] }
  end

  def load_actions
    actions = []
    Dir.glob(File.dirname(__FILE__) + '/' + '../actions/*.yml') do |yml_file|
      actions << YAML.load_file(yml_file)
    end
    actions
  end
end
