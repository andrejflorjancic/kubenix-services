{ name, lib, config, k8s, pkgs, ... }:

with lib;
with k8s;

{
  config.kubernetes.moduleDefinitions.mariadb.module = {name, config, ...}: {
    options = {
      image = mkOption {
        description = "Docker image to use";
        type = types.str;
        default = "mariadb";
      };

      rootPassword = mkSecretOption {
        description = "MariaDB root password";
        default.key = "password";
      };

      mysql = {
        database = mkOption {
          description = "Name of the mysql database to pre-create";
          type = types.nullOr types.str;
          default = null;
        };

        user = mkSecretOption {
          description = "Mysql user to pre-create";
          default = null;
        };

        password = mkSecretOption {
          description = "Mysql password to pre-create";
          default = null;
        };
      };

      storage = {
        class = mkOption {
          description = "Name of the storage class to use";
          type = types.nullOr types.str;
          default = null;
        };

        size = mkOption {
          description = "Storage size";
          type = types.str;
          default = "10Gi";
        };
      };
    };

    config = {
      kubernetes.resources.deployments.mariadb = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          replicas = 1;
          selector.matchLabels.app = name;
          template = {
            metadata.labels.app = name;
            spec = {
              containers.mariadb = {
                image = config.image;
                env = {
                  MYSQL_ROOT_PASSWORD = secretToEnv config.rootPassword;
                  MYSQL_DATABASE.value = config.mysql.database;
                  MYSQL_USER = mkIf (config.mysql.user != null) (secretToEnv config.mysql.user);
                  MYSQL_PASSWORD = mkIf (config.mysql.password != null) (secretToEnv config.mysql.password);
                };
                ports = [{
                  name = "mariadb";
                  containerPort = 3306;
                }];
                volumeMounts = [{
                  name = "data";
                  mountPath = "/var/lib/mysql";
                }];
              };
              volumes.data.persistentVolumeClaim.claimName = name;
            };
          };
        };
      };

      kubernetes.resources.podDisruptionBudgets.mariadb = {
        metadata.name = name;
        metadata.labels.app = name;
        spec.maxUnavailable = 1;
        spec.selector.matchLabels.app = name;
      };

      kubernetes.resources.services.mariadb = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          ports = [{
            port = 3306;
            name = "mariadb";
          }];
          selector.app = name;
        };
      };

      kubernetes.resources.persistentVolumeClaims.mariadb = {
        metadata.name = name;
        metadata.labels.app = name;
        spec = {
          accessModes = ["ReadWriteOnce"];
          resources.requests.storage = config.storage.size;
          storageClassName = config.storage.class;
        };
      };
    };
  };
}
