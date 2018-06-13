#!/usr/bin/ruby
require 'yaml'
require 'pp'
require 'riddl/client'
require 'json'

file = File.read '3a17d071-b756-4ad4-adca-e3e0e2f685ad.xes.yaml'
yaml = YAML.load_stream(file)
yaml.each{|elem|
  if elem&.[]('event')&.[]('cpee:lifecycle:transition') == "activity/receiving" then
    event = elem['event']
    instanceid   = event['trace:id']
    endpoint     = event['concept:endpoint']
    received     = event['list']&.[]('data_receiver')
    activity     = event['id:id']
    uuid         = event['cpee:uuid']
    label        = event['concept:name']
    topic,evname = event['cpee:lifecycle:transition'].split('/')
    notification = JSON.dump({"endpoint" => endpoint, "received" =>received, "instance_uuid" => uuid, "activity" => activity, "label" => label, "instance_name"=>instanceid})
    srv = Riddl::Client.new('http://coms.wst.univie.ac.at:9201')
    res = srv.resource("/")
    status, response = res.post [
      Riddl::Header.new("CPEE_INSTANCE",instanceid),
      Riddl::Header.new("CPEE-BASE","cpee.org:9298"),
      Riddl::Parameter::Simple.new("key","asdfsadf"),
      Riddl::Parameter::Simple.new("topic",topic),
      Riddl::Parameter::Simple.new("event",evname),
      Riddl::Parameter::Simple.new("notification",notification)      
    ]

  end
 }
