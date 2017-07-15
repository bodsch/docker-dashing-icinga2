
require 'icinga2'

icinga_host          = ENV.fetch( 'ICINGA_HOST'             , 'icinga2' )
icinga_api_port      = ENV.fetch( 'ICINGA_API_PORT'         , 5665 )
icinga_api_user      = ENV.fetch( 'ICINGA_API_USER'         , 'admin' )
icinga_api_password  = ENV.fetch( 'ICINGA_API_PASSWORD'     , nil )
icinga_api_pki_path  = ENV.fetch( 'ICINGA_API_PKI_PATH'     , nil )
icinga_api_node_name = ENV.fetch( 'ICINGA_API_NODE_NAME'    , nil )
icinga_cluster       = ENV.fetch( 'ICINGA_CLUSTER'          , false )
icinga_satellite     = ENV.fetch( 'ICINGA_CLUSTER_SATELLITE', nil )

# convert string to bool
icinga_cluster   = icinga_cluster.to_s.eql?('true') ? true : false

config = {
  icinga: {
    host: icinga_host,
    api: {
      port: icinga_api_port,
      user: icinga_api_user,
      password: icinga_api_password,
      pki_path: icinga_api_pki_path,
      node_name: icinga_api_node_name
    },
    cluster: icinga_cluster,
    satellite: icinga_satellite,
  }
}

icinga = Icinga2::Client.new( config )


SCHEDULER.every '15s', :first_in => 10 do |job|

  icinga.extract_data

  # meter widget
  # we'll update the patched meter widget with absolute values (set max dynamically)
  host_problems       = icinga.host_problems      # all hosts with problems (integer)
  max_host_objects    = icinga.hosts_all          # all hosts (integer)
  service_problems    = icinga.service_problems   # all services with problems (integer)
  max_service_objects = icinga.services_all       # all services (integer)

  # check stats
  icinga_stats = [
    { label: 'Host checks/min'    , value: icinga.hosts_active_checks_1min },
    { label: 'Service checks/min' , value: icinga.services_active_checks_1min },
  ]

  # severity list
  problem_services, service_problems_severity = icinga.problem_services(15) # numbers of services with problems (Hash)
  work_queue_stats = icinga.work_queue_statistics

  severity_stats = []
  problem_services.each do |name,state|
    severity_stats.push( { label: Icinga2::Converts.format_service(name) } )
  end

  work_queue_stats.each do |name, value|
    icinga_stats.push( { label: name, value: '%0.2f' % value } )
  end

  # handled stats
  handled_stats = [
    { label: 'Acknowledgements', color: 'blue' },
    { label: 'Hosts'           , value: icinga.hosts_acknowledged},
    { label: 'Services'        , value: icinga.services_acknowledged},
    { label: 'Downtimes'       , color: 'blue' },
    { label: 'Hosts'           , value: icinga.hosts_in_downtime},
    { label: 'Services'        , value: icinga.services_in_downtime},
  ]

#  puts "Severity: #{severity_stats}"
#  puts "Icinga  : #{icinga_stats}"
#  puts "Handled : #{handled_stats}"

  # ================================================================================================
#   puts format('Severity: " + severity_stats.to_s

  send_event('icinga-host-meter', {
    value: host_problems,
    max:   max_host_objects,
    moreinfo: "Total hosts: #{max_host_objects}",
    color: 'blue'
  })

  send_event('icinga-service-meter', {
    value: service_problems,
    max:   max_service_objects,
    moreinfo: "Total services: #{max_service_objects}",
    color: 'blue'
  })

  send_event('icinga-stats', {
    title: "#{icinga.version} (#{icinga.revision})",
    items: icinga_stats,
    moreinfo: "Avg latency: #{icinga.avg_latency.round(2)}s",
    color: 'blue'
  })

  send_event('handled-stats', {
    items: handled_stats,
    color: 'blue'
  })

  send_event('icinga-severity', {
    items: severity_stats,
    color: 'blue'
  })

  host_color = if( icinga.hosts_down.to_i == 0 )
    'blue'
  else
    'red'
  end

  service_color = if( icinga.services_critical.to_i == 0 )
    'blue'
  else
    'red'
  end

  # down, critical, warning, unknown
#  puts format('Host Down: %d', icinga.hosts_down)
  send_event('icinga-host-problems-down', {
    title: 'Hosts down',
    value: icinga.hosts_down,
    moreinfo: "All Problems: #{icinga.hosts_down.to_s}",
    color: host_color
  })

#  puts format('Service Critical: %d', icinga.services_critical)
  send_event('icinga-service-problems-critical', {
    title: 'Services critical',
    value: icinga.services_critical.to_s,
    moreinfo: "All Problems: " + icinga.services_critical.to_s,
    color: service_color
  })

#  puts format('Service Warning: %d', icinga.services_warning)
  send_event('icinga-service-problems-warning', {
    title: 'Services warning',
    value: icinga.services_warning.to_s,
    moreinfo: "All Problems: " + icinga.services_warning.to_s,
    color: 'yellow'
  })

#  puts format('Service Unknown: %d', icinga.services_unknown )
  send_event('icinga-service-problems-unknown', {
    title: 'Services unknown',
    value: icinga.services_unknown.to_s,
    moreinfo: "All Problems: " + icinga.services_unknown.to_s,
    color: 'purple' })

#   # ack, downtime
#   puts format('Service Acknowledged: %d', icinga.services_acknowledged)
#   send_event('icinga-service-ack', {
#     value: icinga.services_acknowledged.to_s,
#     color: 'blue'
#   })
#
#   puts format('Host Acknowledged: %d', icinga.hosts_acknowledged)
#   send_event('icinga-host-ack', {
#     value: icinga.hosts_acknowledged.to_s,
#     color: 'blue'
#   })
#
#   puts format('Service In Downtime: %d', icinga.services_in_downtime)
#   send_event('icinga-service-downtime', {
#     value: icinga.services_in_downtime.to_s,
#     color: 'orange'
#   })
#
#   puts format('Host In Downtime: %d', icinga.hosts_in_downtime)
#   send_event('icinga-host-downtime', {
#     value: icinga.hosts_in_downtime.to_s,
#     color: 'orange'
#   })

end
