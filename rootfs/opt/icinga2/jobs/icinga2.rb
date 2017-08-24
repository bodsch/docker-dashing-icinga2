
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


SCHEDULER.every '20s', :first_in => 0 do |job|

  begin

    icinga.application_data
    icinga.cib_data
    icinga.host_objects

    avg_latency, avg_execution_time = icinga.average_statistics.values
    hosts_active_checks, hosts_passive_checks, services_active_checks, services_passive_checks = icinga.interval_statistics.values

    hosts_up, hosts_down, hosts_pending, hosts_unreachable, hosts_in_downtime, hosts_acknowledged = icinga.host_statistics.values

    host_problems_all, host_problems_down, host_problems_critical, host_problems_unknown = icinga.host_problems.values

    services_ok, services_warning, services_critical, services_unknown, services_pending, services_in_downtime, services_acknowledged = icinga.service_statistics.values

    service_problems_handled_all, service_problems_handled_critical, service_problems_handled_warning, service_problems_handled_unknown = icinga.service_problems_handled.values

    version, revision = icinga.version.values

    # meter widget
    # we'll update the patched meter widget with absolute values (set max dynamically)
    hosts_down          = hosts_down          # all hosts with problems (integer)
    hosts_all           = icinga.hosts_all           # all hosts (integer)
    service_problems    = icinga.count_services_with_problems   # all services with problems (integer)
    services_all        = icinga.services_all        # all services (integer)

    # check stats
    icinga_stats = [
      { label: 'Host checks/min'    , value: hosts_active_checks },
      { label: 'Service checks/min' , value: services_active_checks },
    ]

    # severity list
    problem_services, service_problems_severity = icinga.list_services_with_problems(10).values
    work_queue_stats = icinga.work_queue_statistics

    severity_stats = []
    problem_services.each do |name,state|
      severity_stats.push( { label: Icinga2::Converts.format_service(name) } )
    end

    work_queue_stats.each do |name, value|
      icinga_stats.push( { label: name, value: '%0.2f' % value } )
    end

    hosts_handled_problems, hosts_down_adjusted = icinga.hosts_adjusted.values

    # -----------------------------------------------------------------------------------

    color_hosts_down            = hosts_down.to_i == 0            ? 'nothing' : 'red'
    color_hosts_pending         = hosts_pending.to_i == 0         ? 'nothing' : 'purple'
    color_hosts_unreachable     = hosts_unreachable.to_i == 0     ? 'nothing' : 'purple'
    color_hosts_in_downtime     = hosts_in_downtime.to_i == 0     ? 'nothing' : 'green'
    color_hosts_acknowledged    = hosts_acknowledged.to_i == 0    ? 'nothing' : 'green'

    color_services_warning      = services_warning.to_i == 0      ? 'nothing' : 'yellow'
    color_services_critical     = services_critical.to_i == 0     ? 'nothing' : 'red'
    color_services_unknown      = services_unknown.to_i == 0      ? 'nothing' : 'purple'
    color_services_pending      = services_pending.to_i == 0      ? 'nothing' : 'purple'
    color_services_in_downtime  = services_in_downtime.to_i == 0  ? 'nothing' : 'green'
    color_services_acknowledged = services_acknowledged.to_i == 0 ? 'nothing' : 'green'

    color_hosts_down_adjusted       = hosts_down_adjusted.to_i == 0 ? 'blue' : 'red'
    color_services_handled_critical = service_problems_handled_critical.to_i == 0 ? 'blue' : 'red'
    color_services_handled_warning  = service_problems_handled_warning.to_i == 0 ? 'blue' : 'yellow'
    color_services_handled_unknown  = service_problems_handled_unknown.to_i == 0 ? 'blue' : 'purple'

    # ================================================================================================

    # handled stats
    handled_stats = [
      { label: 'Acknowledgements', color: 'blue' },
      { label: 'Hosts'           , value: hosts_acknowledged},
      { label: 'Services'        , value: services_acknowledged},
      { label: 'Downtimes'       , color: 'blue' },
      { label: 'Hosts'           , value: hosts_in_downtime},
      { label: 'Services'        , value: services_in_downtime},
    ]

    hosts_data = [
      { label: 'Up'          , value: hosts_up },
      { label: 'Down'        , value: hosts_down, handled: 0, color: color_hosts_down },
      { label: 'Pending'     , value: hosts_pending, color: color_hosts_pending },
      { label: 'Unreachable' , value: hosts_unreachable, color: color_hosts_unreachable },
      { label: 'In Downtime' , value: hosts_in_downtime, color: color_hosts_in_downtime },
      { label: 'Acknowledged', value: hosts_acknowledged, color: color_hosts_acknowledged },
    ]

    services_data = [
      { label: 'ok'          , value: services_ok },
      { label: 'warning'     , value: services_warning, color: color_services_warning },
      { label: 'critical'    , value: services_critical, color: color_services_critical },
      { label: 'unknown'     , value: services_unknown, color: color_services_unknown },
      { label: 'pending'     , value: services_pending, color: color_services_pending },
      { label: 'in downtime' , value: services_in_downtime, color: color_services_in_downtime },
      { label: 'Acknowledged', value: services_acknowledged, color: color_services_acknowledged }
    ]
    # -----------------------------------------------------------------------------------
#     puts "Severity: #{severity_stats}"
#     puts "Icinga  : #{icinga_stats}"
#     puts "Handled : #{handled_stats}"
#     puts "hosts_adjusted    : #{icinga.hosts_adjusted}"
#     puts "services_adjusted : #{icinga.services_adjusted}"
#     puts "host_statistics   : #{icinga.host_statistics}"
#     puts "service_statistics: #{icinga.service_statistics}"
#     puts "service handled critical: " + service_problems_handled_critical.to_s
#     puts "service handled warnings: " + service_problems_handled_warning.to_s
#     puts "service handled unknowns: " + service_problems_handled_unknown.to_s
#     puts format('Severity: " + severity_stats.to_s
#     puts format('Host Down: %d', hosts_down)
#     puts format('Service Critical: %d', icinga.services_critical)
#     puts format('Service Warning: %d', icinga.services_warning)
#     puts format('Service Unknown: %d', icinga.services_unknown )
#     puts format('Service Acknowledged: %d', services_acknowledged)
#     puts format('Host Acknowledged: %d', hosts_acknowledged)
#     puts format('Service In Downtime: %d', services_in_downtime)
#     puts format('Host In Downtime: %d', hosts_in_downtime)
    # -----------------------------------------------------------------------------------

    send_event('icinga-host-meter', {
      value: hosts_down,
      max:   hosts_all,
      moreinfo: "Total hosts: #{hosts_all}",
      color: 'blue'
    })

    send_event('icinga-service-meter', {
      value: service_problems,
      max:   services_all,
      moreinfo: "Total services: #{services_all}",
      color: 'blue'
    })

    send_event('icinga-stats', {
      title: "version: #{version}",
      items: icinga_stats,
      moreinfo: "Avg latency: #{avg_latency.to_f.round(2)}s",
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

    send_event('icinga-hosts', {
      title: format( '%d Hosts', icinga.hosts_all ),
      items: hosts_data
    })

    send_event('icinga-services', {
      title: format( '%d Services', icinga.services_all ),
      items: services_data
    })

    # down, critical, warning, unknown
    send_event('icinga-host-problems-down', {
      title: 'Hosts down',
      value: hosts_down,
      moreinfo: "All Problems: #{host_problems_all.to_s}",
      color: color_hosts_down
    })

    send_event('icinga-service-problems-critical', {
      title: 'Services critical',
      value: service_problems_handled_critical.to_s,
      moreinfo: "All Problems: " + services_critical.to_s,
      color: color_services_handled_critical
    })

    send_event('icinga-service-problems-warning', {
      title: 'Services warning',
      value: service_problems_handled_warning.to_s,
      moreinfo: "All Problems: " + services_warning.to_s,
      color: color_services_handled_warning
    })

    send_event('icinga-service-problems-unknown', {
      title: 'Services unknown',
      value: service_problems_handled_unknown.to_s,
      moreinfo: "All Problems: " + services_unknown.to_s,
      color: color_services_handled_unknown
    })

    # ack, downtime
    send_event('icinga-service-ack', {
      value: services_acknowledged.to_s,
      color: 'blue'
    })

    send_event('icinga-host-ack', {
      value: hosts_acknowledged.to_s,
      color: 'blue'
    })

    send_event('icinga-service-downtime', {
      value: services_in_downtime.to_s,
      color: 'orange'
    })

    send_event('icinga-host-downtime', {
      value: hosts_in_downtime.to_s,
      color: 'orange'
    })

  rescue => e
    $stderr.puts( e )

  end

end
