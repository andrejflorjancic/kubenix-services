{ config, lib, k8s, ... }:

with lib;

{
  config.kubernetes.moduleDefinitions.zetcd.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Name of the zetcd image to use";
        type = types.str;
        default = "quay.io/coreos/zetcd";
      };

      replicas = mkOption {
        description = "Number of zetcd replicas";
        type = types.int;
        default = 3;
      };

      endpoints = mkOption {
        description = "Etcd endpoints";
        type = types.listOf types.str;
        default = ["etcd:2379"];
      };

      namespace = mkOption {
        description = "Name of the namespace where to deploy zetcd";
        type = types.str;
        default = "default";
      };
    };

    config = {
      kubernetes.resources.deployments.zetcd = {
        metadata.name = name;
        metadata.namespace = mkDefault config.namespace;
        metadata.labels.app = name;
        spec = {
          template = {
            metadata.labels.app = name;
            spec = {
              containers.filebeat = {
                image = config.image;
                command = [
                  "zetcd" "--zkaddr" "0.0.0.0:2181"
                  "--endpoints" (concatStringsSep "," config.endpoints)
                ];

                resources.requests = {
                  cpu = "100m";
                  memory = "100Mi";
                };
              };
            };
          };
        };
      };

      kubernetes.resources.services.zetcd = {
        metadata.name = name;
        metadata.namespace = mkDefault config.namespace;
        metadata.labels.app = name;
        spec = {
          selector.app = name;
          ports = [{
            protocol = "TCP";
            port = 2181;
          }];
        };
      };
    };
  };
}
