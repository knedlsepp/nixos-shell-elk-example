{ pkgs, ... }: {
  users.users.root.password = "root";
  virtualisation.memorySize = 4096;
  virtualisation = {
    forwardPorts = [
      { from = "host"; host.port = 2222; guest.port = 22; }
      { from = "host"; host.port = 9200; guest.port = 9200; }
      { from = "host"; host.port = 9300; guest.port = 9300; }
      { from = "host"; host.port = 9600; guest.port = 9600; }
    ];
  };
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [
    "nodejs-16.20.2"
  ];

  services =
    let
      esUrl = "http://localhost:9200";
      elk = {
        elasticsearch = pkgs.elasticsearch7;
        logstash = pkgs.logstash7;
        kibana = pkgs.kibana7;
        filebeat = pkgs.filebeat7;
        metricbeat = pkgs.metricbeat7;
      };
    in
    { openssh.enable = true; } //
    {
      # Copied from nixpkgs/nixos/tests/elk.nix

      journalbeat = {
        enable = elk ? journalbeat;
        package = elk.journalbeat;
        extraConfig = pkgs.lib.mkOptionDefault (
          ''
            logging:
              to_syslog: true
              level: warning
              metrics.enabled: false
            output.elasticsearch:
              hosts: [ "127.0.0.1:9200" ]
            journalbeat.inputs:
            - paths: []
              seek: cursor
          ''
        );
      };

      filebeat = {
        enable = elk ? filebeat;
        package = elk.filebeat;
        inputs.journald.id = "everything";

        inputs.log = {
          enabled = true;
          paths = [
            "/var/lib/filebeat/test"
          ];
        };

        settings = {
          logging.level = "info";
        };
      };

      metricbeat = {
        enable = true;
        package = elk.metricbeat;
        modules.system = {
          metricsets = [ "cpu" "load" "memory" "network" "process" "process_summary" "uptime" "socket_summary" ];
          enabled = true;
          period = "5s";
          processes = [ ".*" ];
          cpu.metrics = [ "percentages" "normalized_percentages" ];
          core.metrics = [ "percentages" ];
        };
        settings = {
          output.elasticsearch = {
            hosts = [ "127.0.0.1:9200" ];
          };
        };
      };

      logstash = {
        enable = true;
        package = elk.logstash;
        listenAddress = "0.0.0.0";
        inputConfig = ''
          exec { command => "echo -n flowers" interval => 1 type => "test" }
          exec { command => "echo -n dragons" interval => 1 type => "test" }
        '';
        filterConfig = ''
          if [message] =~ /dragons/ {
            drop {}
          }
        '';
        outputConfig = ''
          file {
            path => "/tmp/logstash.out"
            codec => line { format => "%{message}" }
          }
          elasticsearch {
            hosts => [ "${esUrl}" ]
          }
        '';
      };

      elasticsearch = {
        enable = true;
        package = elk.elasticsearch;
        listenAddress = "0.0.0.0";
      };

      kibana = {
        enable = true; # FIXME
        package = elk.kibana;
        listenAddress = "0.0.0.0";
        elasticsearch.certificateAuthorities = [];
      };

      elasticsearch-curator = {
        enable = true;
        actionYAML = ''
          ---
          actions:
            1:
              action: delete_indices
              description: >-
                Delete indices older than 1 second (based on index name), for logstash-
                prefixed indices. Ignore the error if the filter does not result in an
                actionable list of indices (ignore_empty_list) and exit cleanly.
              options:
                allow_ilm_indices: true
                ignore_empty_list: True
                disable_action: False
              filters:
              - filtertype: pattern
                kind: prefix
                value: logstash-
              - filtertype: age
                source: name
                direction: older
                timestring: '%Y.%m.%d'
                unit: seconds
                unit_count: 1
        '';
      };
    };
}
