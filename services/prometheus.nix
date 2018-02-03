{ config, lib, k8s, ... }:

with k8s;
with lib;

{
  config.kubernetes.moduleDefinitions.prometheus.module = {name, config, module, ...}: let
    prometheusConfig = {
      global.external_labels = config.externalLabels;

      rule_files = ["/etc/config/*.rules" "/etc/config/*.alerts"];

      scrape_configs = [

        # Scrape config for prometheus itself
        {
          job_name = "prometheus";
          static_configs = [{
            targets = ["localhost:9090"];
          }];
        }
      ] ++ config.extraScrapeConfigs;
      };
  in {
    options = {
      image = mkOption {
        description = "Docker image to use for prometheus";
        type = types.str;
        default = "prom/prometheus:v1.5.2";
      };

      replicas = mkOption {
        description = "Number of prometheus replicas to run";
        type = types.int;
        default = 2;
      };

      alertmanager = {
        enable = mkOption {
          description = "Whether to enable prometheus alertmanager";
          default = false;
          type = types.bool;
        };

        url = mkOption {
          description = "Alertmanager url";
          default = "http://prometheus-alertmanager:9093";
          type = types.str;
        };
      };

      externalLabels = mkOption {
        description = "Attribute set of global labels";
        type = types.attrs;
        default = {};
      };

      rules = mkOption {
        description = "Attribute set of prometheus recording rules to deploy";
        default = {};
      };

      alerts = mkOption {
        description = "Attribute set of alert rules to deploy";
        default = {};
      };

      storage = {
        size = mkOption {
          description = "Prometheus storage size";
          default = "20Gi";
          type = types.str;
        };

        class = mkOption {
          description = "prometheus storage class";
          type = types.nullOr types.str;
          default = null;
        };
      };

      extraArgs = mkOption {
        description = "Prometheus server additional options";
        default = [];
        type = types.listOf types.str;
      };

      extraConfig = mkOption {
        description = "Prometheus extra config";
        type = types.attrs;
        default = {};
      };

      extraScrapeConfigs = mkOption {
        description = "Prometheus extra scrape configs";
        type = types.listOf types.attrs;
        default = [];
      };
    };

    config = {
      kubernetes.resources.statefulSets.prometheus = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          serviceName = name;
          replicas = config.replicas;
          selector.matchLabels.app = name;
          podManagementPolicy = "Parallel";
          template = {
            metadata.name = name;
            metadata.labels.app = name;
            spec = {
              serviceAccountName = name;
              volumes.config.configMap.name = name;

              containers.server-reload = {
                image = "jimmidyson/configmap-reload:v0.1";
                args = [
                  "--volume-dir=/etc/config"
                  "--webhook-url=http://localhost:9090/-/reload"
                ];
                volumeMounts = [{
                  name = "config";
                  mountPath = "/etc/config";
                  readOnly = true;
                }];
              };

              containers.prometheus = {
                image = config.image;
                args = [
                  "--config.file=/etc/config/prometheus.json"
                  "--storage.local.path=/data"
                  "--web.console.libraries=/etc/prometheus/console_libraries"
                  "--web.console.templates=/etc/prometheus/consoles"
                ] ++ (optionals (config.alertmanager.enable) [
                  "--alertmanager.url=${config.alertmanager.url}"
                ]) ++ config.extraArgs;
                ports = [{
                  name = "prometheus";
                  containerPort = 9090;
                }];
                volumeMounts = {
                  export = {
                    name = "storage";
                    mountPath = "/data";
                  };
                  config = {
                    name = "config";
                    mountPath = "/etc/config";
                  };
                };
                readinessProbe = {
                  httpGet = {
                    path = "/status";
                    port = 9090;
                  };
                  initialDelaySeconds = 30;
                  timeoutSeconds = 30;
                };
              };
            };
          };

          volumeClaimTemplates = [{
            metadata.name = "storage";
            spec = {
              accessModes = ["ReadWriteOnce"];
              resources.requests.storage = config.storage.size;
              storageClassName = mkIf (config.storage.class != null) config.storage.class;
            };
          }];
        };
      };

      kubernetes.resources.serviceAccounts.prometheus.metadata.name = name;

      kubernetes.resources.services.prometheus = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          ports = [{
            name = "prometheus";
            port = 9090;
            targetPort = 9090;
            protocol = "TCP";
          }];
          selector.app = name;
        };
      };

      kubernetes.resources.configMaps.prometheus = {
        metadata.name = name;
        metadata.labels.app = name;
        data = {
          "prometheus.json" = builtins.toJSON prometheusConfig;
        } // (mapAttrs (name: value: 
          if isString value then value
          else builtins.readFile value
        ) config.alerts) // (mapAttrs (name: value: 
          if isString value then value
          else builtins.readFile value
        ) config.rules);
      };

      kubernetes.resources.clusterRoleBindings.prometheus = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = name;
        metadata.labels.app = name;
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "prometheus";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = "prometheus";
          namespace = module.namespace;
        }];
      };

      kubernetes.resources.clusterRoles.prometheus = {
        apiVersion = "rbac.authorization.k8s.io/v1beta1";
        metadata.name = name;
        metadata.labels.app = name;
        rules = [{
          apiGroups = [""];
          resources = [
            "nodes"
            "nodes/metrics"
            "nodes/proxy"
            "services"
            "endpoints"
            "pods"
          ];
          verbs = ["get" "list" "watch"];
        } {
          apiGroups = [""];
          resources = [
            "configmaps"
          ];
          verbs = ["get"];
        } {
          nonResourceURLs = ["/metrics"];
          verbs = ["get"];
        }];
      };
    };
  };

  config.kubernetes.moduleDefinitions.prometheus-pushgateway.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Image to use for prometheus pushgateway";
        type = types.str;
        default = "prom/pushgateway:v0.4.0";
      };

      replicas = mkOption {
        description = "Number of prometheus gateway replicas";
        type = types.int;
        default = 1;
      };
    };

    config = {
      kubernetes.resources.deployments.prometheus-pushgateway = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          replicas = config.replicas;
          selector.matchLabels.app = name;
          template = {
            metadata.name = name;
            metadata.labels.app = name;
            spec = {
              containers.prometheus = {
                image = config.image;
                ports = [{
                  name = "prometheus-push";
                  containerPort = 9091;
                }];
                readinessProbe = {
                  httpGet = {
                    path = "/#/status";
                    port = 9091;
                  };
                  initialDelaySeconds = 10;
                  timeoutSeconds = 10;
                };
                resources = {
                  requests = {
                    memory = "128Mi";
                    cpu = "10m";
                  };
                  limits = {
                    memory = "128Mi";
                    cpu = "10m";
                  };
                };
              };
            };
          };
        };
      };

      kubernetes.resources.services.prometheus-pushgateway = {
        metadata.name = name;
        metadata.labels.app = name;
        metadata.annotations."prometheus.io/probe" = "pushgateway";
        metadata.annotations."prometheus.io/scrape" = "true";
        spec = {
          ports = [{
            name = "prometheus-push";
            port = 9091;
            targetPort = 9091;
            protocol = "TCP";
          }];
          selector.app = name;
        };
      };
    };
  };

  config.kubernetes.moduleDefinitions.prometheus-node-exporter.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Prometheus node export image to use";
        type = types.str;
        default = "prom/node-exporter:v0.13.0";
      };

      ignoredMountPoints = mkOption {
        description = "Regex for ignored mount points";
        type = types.str;

        # this is ugly negative regex that ignores everyting except /host/.*
        default = "^/(([h][^o]?(/.+)?)|([h][o][^s]?(/.+)?)|([h][o][s][^t]?(/.+)?)|([^h]?[^o]?[^s]?[^t]?(/.+)?)|([^h][^o][^s][^t](/.+)?))$";
      };

      ignoredFsTypes = mkOption {
        description = "Regex of ignored filesystem types";
        type = types.str;
        default = "^(proc|sys|cgroup|securityfs|debugfs|autofs|tmpfs|sysfs|binfmt_misc|devpts|overlay|mqueue|nsfs|ramfs|hugetlbfs|pstore)$";
      };

      extraPaths = mkOption {
        description = "Extra node-exporter host paths";
        default = {};
        type = types.attrsOf (types.submodule ({name, config, ...}: {
          options = {
            hostPath = mkOption {
              description = "Host path to mount";
              type = types.path;
            };

            mountPath = mkOption {
              description = "Path where to mount";
              type = types.path;
              default = "/host/${name}";
            };
          };
        }));
      };

      extraArgs = mkOption {
        description = "Prometheus node exporter extra arguments";
        type = types.listOf types.str;
        default = [];
      };
    };

    config = {
      kubernetes.resources.daemonSets.prometheus-node-exporter = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          selector.matchLabels.app = name;
          template = {
            metadata.name = name;
            metadata.labels.app = name;
            spec = {
              containers.node-exporter = {
                image = config.image;
                args = [
                  "--collector.procfs=/host/proc"
                  "--collector.sysfs=/host/sys"
                  "--collector.filesystem.ignored-mount-points=${config.ignoredMountPoints}"
                  "--collector.filesystem.ignored-fs-types=${config.ignoredFsTypes}"
                ] ++ config.extraArgs;
                ports = [{
                  name = "node-exporter";
                  containerPort = 9100;
                }];
                livenessProbe = {
                  httpGet = {
                    path = "/metrics";
                    port = 9100;
                  };
                  initialDelaySeconds = 30;
                  timeoutSeconds = 1;
                };
                volumeMounts = [{
                  name = "proc";
                  mountPath = "/host/proc";
                  readOnly = true;
                } {
                  name = "sys";
                  mountPath = "/host/sys";
                  readOnly = true;
                }] ++ (mapAttrsToList (name: path: {
                  inherit name;
                  inherit (path) mountPath;
                  readOnly = true;
                }) config.extraPaths);
              };
              hostPID = true;
              volumes = {
                proc.hostPath.path = "/proc";
                sys.hostPath.path = "/sys";
              }// (mapAttrs (name: path: {
                hostPath.path = path.hostPath;
              }) config.extraPaths);
            };
          };
        };
      };

      kubernetes.resources.services.prometheus-node-exporter = {
        metadata.name = name;
        metadata.labels.app = name;
        metadata.annotations."prometheus.io/scrape" = "true";
        spec = {
          ports = [{
            name = "node-exporter";
            port = 9100;
            targetPort = 9100;
            protocol = "TCP";
          }];
          selector.app = name;
        };
      };
    };
  };

  config.kubernetes.moduleDefinitions.prometheus-alertmanager.module = {name, config, ...}: let
    routeOptions = {
      receiver = mkOption {
        description = "Which prometheus alertmanager receiver to use";
        type = types.str;
        default = "default";
      };

      groupBy = mkOption {
        description = "Group by alerts by field";
        default = [];
        type = types.listOf types.str;
      };

      continue = mkOption {
        description = "Whether an alert should continue matching subsequent sibling nodes";
        default = false;
        type = types.bool;
      };

      match = mkOption {
        description = "A set of equality matchers an alert has to fulfill to match the node";
        type = types.attrsOf types.str;
        default = {};
      };

      matchRe = mkOption {
        description = "A set of regex-matchers an alert has to fulfill to match the node.";
        type = types.attrsOf types.str;
        default = {};
      };

      groupWait = mkOption {
        description = "How long to initially wait to send a notification for a group of alerts.";
        type = types.str;
        default = "10s";
      };

      groupInterval = mkOption {
        description = ''
          How long to wait before sending a notification about new alerts that
          are added to a group of alerts for which an initial notification has
          already been sent. (Usually ~5min or more.)
        '';
        type = types.str;
        default = "5m";
      };

      repeatInterval = mkOption {
        description = ''
          How long to wait before sending a notification again if it has already
          been sent successfully for an alert. (Usually ~3h or more).
        '';
        type = types.str;
        default = "3h";
      };

      routes = mkOption {
        type = types.attrsOf (types.submodule {
          options = routeOptions;
        });
        description = "Child routes";
        default = {};
      };
    };

    mkRoute = cfg: {
      receiver = cfg.receiver;
      group_by = cfg.groupBy;
      continue = cfg.continue;
      match = cfg.match;
      match_re = cfg.matchRe;
      group_wait = cfg.groupWait;
      group_interval = cfg.groupInterval;
      repeat_interval = cfg.repeatInterval;
      routes = mapAttrsToList (name: route: mkRoute route) cfg.routes;
    };

    mkInhibitRule = cfg: {
      target_match = cfg.targetMatch;
      target_match_re = cfg.targetMatchRe;
      source_match = cfg.sourceMatch;
      source_match_re = cfg.sourceMatchRe;
      equal = cfg.equal;
    };

    mkReceiver = cfg: {
      name = cfg.name;
    } // optionalAttrs (cfg.type != null) {
      "${cfg.type}_configs" = [cfg.options];
    };

    alertmanagerConfig = {
      global = {
        resolve_timeout = config.resolveTimeout;
      };
      route = mkRoute config.route;
      receivers = mapAttrsToList (name: value: mkReceiver value) config.receivers;
      inhibit_rules = mapAttrsToList (name: value: mkInhibitRule value) config.inhibitRules;
      templates = config.templates;
    };
  in {
    options = {
      image = mkOption {
        description = "Prometheus alertmanager image to use";
        type = types.str;
        default = "prom/alertmanager:v0.8.0";
      };

      replicas = mkOption {
        description = "Number of prometheus alertmanager replicas";
        type = types.int;
        default = 2;
      };

      resolveTimeout = mkOption {
        description = ''
          ResolveTimeout is the time after which an alert is declared resolved
          if it has not been updated.
        '';
        type = types.str;
        default = "5m";
      };

      receivers = mkOption {
        description = "Prometheus receivers";
        default = {};
        type = types.attrsOf (types.submodule ({name, config, ... }: {
          options = {
            name = mkOption {
              description = "Unique name of the receiver";
              type = types.str;
              default = name;
            };

            type = mkOption {
              description = "Receiver name (defaults to attr name)";
              type = types.nullOr (types.enum ["email" "hipchat" "pagerduty" "pushover" "slack" "opsgenie" "webhook" "victorops"]);
              default = null;
            };

            options = mkOption {
              description = "Reciver options";
              type = types.attrs;
              default = {};
              example = literalExample ''
                {
                  room_id = "System notiffications";
                  auth_token = "token";
                }
              '';
            };
          };
        }));
      };

      route = routeOptions;

      inhibitRules = mkOption {
        description = "Attribute set of alertmanager inhibit rules";
        default = {};
        type = types.attrsOf (types.submodule {
          options = {
            targetMatch = mkOption {
              description = "Matchers that have to be fulfilled in the alerts to be muted";
              type = types.attrsOf types.str;
              default = {};
            };

            targetMatchRe = mkOption {
              description = "Regex matchers that have to be fulfilled in the alerts to be muted";
              type = types.attrsOf types.str;
              default = {};
            };

            sourceMatch = mkOption {
              description = "Matchers for which one or more alerts have to exist for the inhibition to take effect.";
              type = types.attrsOf types.str;
              default = {};
            };

            sourceMatchRe = mkOption {
              description = "Regex matchers for which one or more alerts have to exist for the inhibition to take effect.";
              type = types.attrsOf types.str;
              default = {};
            };

            equal = mkOption {
              description = "Labels that must have an equal value in the source and target alert for the inhibition to take effect.";
              type = types.listOf types.str;
              default = [];
            };
          };
        });
      };

      templates = mkOption {
        description = ''
          Files from which custom notification template definitions are read.
          The last component may use a wildcard matcher, e.g. 'templates/*.tmpl'.
        '';
        type = types.listOf types.path;
        default = [];
      };

      storage = {
        size = mkOption {
          description = "Prometheus alertmanager storage size";
          default = "2Gi";
          type = types.str;
        };

        class = mkOption {
          description = "Prometheus alertmanager storage class";
          type = types.nullOr types.str;
          default = null;
        };
      };

      extraArgs = mkOption {
        description = "Prometheus server additional options";
        default = [];
        type = types.listOf types.str;
      };

      extraConfig = mkOption {
        description = "Prometheus extra config";
        type = types.attrs;
        default = {};
      };
    };

    config = {
      kubernetes.resources.statefulSets.prometheus-alertmanager = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          replicas = config.replicas;
          serviceName = name;
          selector.matchLabels.app = name;
          template = {
            metadata.name = name;
            metadata.labels.app = name;
            spec = {
              volumes.config.configMap.name = name;

              containers.server-reload = {
                image = "jimmidyson/configmap-reload:v0.1";
                args = [
                  "--volume-dir=/etc/config"
                  "--webhook-url=http://localhost:9093/-/reload"
                ];
                volumeMounts = [{
                  name = "config";
                  mountPath = "/etc/config";
                  readOnly = true;
                }];
              };

              containers.alertmanager = {
                image = config.image;
                args = [
                  "--config.file=/etc/config/alertmanager.json"
                  "--storage.path=/data"
                ] ++ config.extraArgs;
                ports = [{
                  name = "alertmanager";
                  containerPort = 9093;
                }];
                livenessProbe = {
                  httpGet = {
                    path = "/";
                    port = 9093;
                  };
                  initialDelaySeconds = 30;
                  timeoutSeconds = 30;
                };
                volumeMounts = {
                  export = {
                    name = "storage";
                    mountPath = "/data";
                  };
                  config = {
                    name = "config";
                    mountPath = "/etc/config";
                    readOnly = true;
                  };
                };
              };
            };
          };

          volumeClaimTemplates = [{
            metadata.name = "storage";
            spec = {
              accessModes = ["ReadWriteOnce"];
              resources.requests.storage = config.storage.size;
              storageClassName = mkIf (config.storage.class != null) config.storage.class;
            };
          }];
        };
      };

      kubernetes.resources.configMaps.prometheus-alertmanager = {
        metadata.name = name;
        metadata.labels.app = name;
        data."alertmanager.json" = builtins.toJSON alertmanagerConfig;
      };

      kubernetes.resources.services.prometheus-alertmanager = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          ports = [{
            name = "alertmanager";
            port = 9093;
            targetPort = 9093;
            protocol = "TCP";
          }];
          selector.app = name;
        };
      };
    };
  };
}