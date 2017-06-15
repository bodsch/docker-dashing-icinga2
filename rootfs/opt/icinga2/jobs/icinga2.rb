
require 'icinga2'

icinga_host         = ENV.fetch( 'ICINGA_HOST'             , 'icinga2' )
icinga_api_port     = ENV.fetch( 'ICINGA_API_PORT'         , 5665 )
icinga_api_user     = ENV.fetch( 'ICINGA_API_USER'         , 'admin' )
icinga_api_password = ENV.fetch( 'ICINGA_API_PASSWORD'     , nil )
icinga_cluster      = ENV.fetch( 'ICINGA_CLUSTER'          , false )
icinga_satellite    = ENV.fetch( 'ICINGA_CLUSTER_SATELLITE', nil )


# convert string to bool
icinga_cluster   = icinga_cluster.to_s.eql?('true') ? true : false

config = {
  :icinga => {
    :host      => icinga_host,
    :api       => {
      :port => icinga_api_port,
      :user => icinga_api_user,
      :password => icinga_api_password
    },
    :cluster   => icinga_cluster,
    :satellite => icinga_satellite,
  }
}

icinga = Icinga2::Client.new( config )


SCHEDULER.every '5s', :first_in => 0 do |job|

  cib = icinga.cib_data()
  app = icinga.application_data()

  if( cib.is_a?(String) )
    cib = JSON.parse(cib)
  end

  # meter widget
  # we'll update the patched meter widget with absolute values (set max dynamically)
  host_problems      = icinga.host_problems()
  max_host_objects    = icinga.host_objects()

  service_problems   = icinga.service_problems()
  max_service_objects = icinga.service_objects()

  if( max_host_objects.is_a?(String) )
    max_host_objects = JSON.parse(max_host_objects)
  end
  if( max_service_objects.is_a?(String) )
    max_service_objects = JSON.parse(max_service_objects)
  end

  max_host_objects    = max_host_objects.dig('nodes').keys.count
  max_service_objects = max_service_objects.dig('nodes').keys.count

  # check stats
  check_stats = [
    {'label' => 'Host (active)'    , 'value' => cib.dig('status','active_host_checks_1min')},
    {'label' => 'Service (active)' , 'value' => cib.dig('status','active_service_checks_1min')},
  ]

  # severity list
  problem_services    = icinga.problem_services()
  severity_stats = []

  problem_services.each do |name,state|
    severity_stats.push({ 'label' => Icinga2::Converts.format_service(name) })
  end

  puts "Severity: " + severity_stats.to_s

  send_event('icinga-host-meter', {
   value: host_problems,
   max:   max_host_objects,
   moreinfo: "Total hosts: #{max_host_objects}",
   color: 'blue' })

  send_event('icinga-service-meter', {
   value: service_problems,
   max:   max_service_objects,
   moreinfo: "Total services: #{max_service_objects}",
   color: 'blue' })


  send_event('icinga-checks', {
   items: check_stats,
   moreinfo: "Avg latency: #{cib.dig('status','avg_latency').round(2)}s",
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
