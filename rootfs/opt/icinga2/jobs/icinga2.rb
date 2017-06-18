
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

  cib_status = cib.dig('status')

  # meter widget
  # we'll update the patched meter widget with absolute values (set max dynamically)
  host_problems       = icinga.host_problems
  max_host_objects    = icinga.host_objects
  service_problems    = icinga.service_problems
  max_service_objects = icinga.service_objects

  max_host_objects    = max_host_objects.dig(:nodes).count
  max_service_objects = max_service_objects.dig(:nodes).count

  # check stats
  check_stats = [
    {'label' => 'Host (active)'    , 'value' => cib_status.dig('active_host_checks_1min')},
    {'label' => 'Service (active)' , 'value' => cib_status.dig('active_service_checks_1min')},
  ]

  # severity list
  problem_services    = icinga.problem_services()
  severity_stats = []

  problem_services.each do |name,state|
    severity_stats.push({ 'label' => Icinga2::Converts.format_service(name) })
  end

#   puts "Severity: " + severity_stats.to_s

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
   moreinfo: "Avg latency: #{cib_status.dig('avg_latency').round(2)}s",
   color: 'blue' })

  send_event('icinga-severity', {
   items: severity_stats,
   color: 'blue' })

  # down, critical, warning, unknown
  send_event('icinga-host-down', {
   value: cib_status.dig('num_hosts_down'),
   color: 'red' })

  send_event('icinga-service-critical', {
   value: cib_status.dig('num_services_critical'),
   color: 'red' })

  send_event('icinga-service-warning', {
   value: cib_status.dig('num_services_warning'),
   color: 'yellow' })


  send_event('icinga-service-unknown', {
   value: cib_status.dig('num_services_unknown'),
   color: 'purple' })

  # ack, downtime
  send_event('icinga-service-ack', {
   value: cib_status.dig('num_services_acknowledged'),
   color: 'blue' })

  send_event('icinga-host-ack', {
   value: cib_status.dig('num_hosts_acknowledged'),
   color: 'blue' })

  send_event('icinga-service-downtime', {
   value: cib_status.dig('num_services_in_downtime'),
   color: 'orange' })

  send_event('icinga-host-downtime', {
   value: cib_status.dig('num_hosts_in_downtime'),
   color: 'orange' })

end
