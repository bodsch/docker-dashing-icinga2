
require 'icinga2'

icingaHost         = ENV.fetch( 'ICINGA_HOST'             , 'icinga2' )
icingaApiPort      = ENV.fetch( 'ICINGA_API_PORT'         , 5665 )
icingaApiUser      = ENV.fetch( 'ICINGA_API_USER'         , 'admin' )
icingaApiPass      = ENV.fetch( 'ICINGA_API_PASSWORD'     , nil )
icingaCluster      = ENV.fetch( 'ICINGA_CLUSTER'          , false )
icingaSatellite    = ENV.fetch( 'ICINGA_CLUSTER_SATELLITE', nil )


# convert string to bool
icingaCluster   = icingaCluster.to_s.eql?('true') ? true : false

config = {
  :icinga => {
    :host      => icingaHost,
    :api       => {
      :port => icingaApiPort,
      :user => icingaApiUser,
      :password => icingaApiPass
    },
    :cluster   => icingaCluster,
    :satellite => icingaSatellite,
  }
}

icinga = Icinga2::Client.new( config )


SCHEDULER.every '15s', :first_in => 0 do |job|

  cib = icinga.CIBData()
  app = icinga.applicationData()

  if( cib.is_a?(String) )
    cib = JSON.parse(cib)
  end

  # meter widget
  # we'll update the patched meter widget with absolute values (set max dynamically)
  hostProblems      = icinga.hostProblems()
  maxHostObjects    = icinga.hostObjects()

  serviceProblems   = icinga.serviceProblems()
  maxServiceObjects = icinga.serviceObjects()

  if( maxHostObjects.is_a?(String) )
    maxHostObjects = JSON.parse(maxHostObjects)
  end
  if( maxServiceObjects.is_a?(String) )
    maxServiceObjects = JSON.parse(maxServiceObjects)
  end

  maxHostObjects    = maxHostObjects.dig('nodes').keys.count
  maxServiceObjects = maxServiceObjects.dig('nodes').keys.count

  # check stats
  check_stats = [
    {'label' => 'Host (active)'    , 'value' => cib.dig('status','active_host_checks_1min')},
    {'label' => 'Service (active)' , 'value' => cib.dig('status','active_service_checks_1min')},
  ]

  # severity list
  problemServ    = icinga.problemServices()
  severity_stats = []

  problemServ.each do |name,state|
    severity_stats.push({ 'label' => Icinga2::Converts.formatService(name) })
  end

  puts "Severity: " + severity_stats.to_s

  send_event('icinga-host-meter', {
   value: hostProblems,
   max:   maxHostObjects,
   moreinfo: "Total hosts: #{maxHostObjects}",
   color: 'blue' })

  send_event('icinga-service-meter', {
   value: serviceProblems,
   max:   maxServiceObjects,
   moreinfo: "Total services: #{maxServiceObjects}",
   color: 'blue' })


  send_event('icinga-checks', {
   items: check_stats,
   moreinfo: "Avg latency: #{cib.dig('status','avg_latency').round(2)}s",
   color: 'blue' })

  send_event('icinga-severity', {
   items: severity_stats,
   color: 'blue' })

  # down, critical, warning, unknown
  send_event('icinga-host-down', {
   value: cib.dig('status','num_hosts_down'),
   color: 'red' })

  send_event('icinga-service-critical', {
   value: cib.dig('status','num_services_critical'),
   color: 'red' })

  send_event('icinga-service-warning', {
   value: cib.dig('status','num_services_warning'),
   color: 'yellow' })


  send_event('icinga-service-unknown', {
   value: cib.dig('status','num_services_unknown'),
   color: 'purple' })

  # ack, downtime
  send_event('icinga-service-ack', {
   value: cib.dig('status','num_services_acknowledged'),
   color: 'blue' })

  send_event('icinga-host-ack', {
   value: cib.dig('status','num_hosts_acknowledged'),
   color: 'blue' })

  send_event('icinga-service-downtime', {
   value: cib.dig('status','num_services_in_downtime'),
   color: 'orange' })

  send_event('icinga-host-downtime', {
   value: cib.dig('status','num_hosts_in_downtime'),
   color: 'orange' })

end
