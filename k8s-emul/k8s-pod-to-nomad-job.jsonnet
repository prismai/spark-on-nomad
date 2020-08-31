local MHZ_PER_CPU = 3000;

local configmaps_consul_prefix = std.extVar("configmaps_consul_prefix");
local k8s_namespace = std.extVar("k8s_namespace");
local k8s_pod = std.parseJson(std.extVar("k8s_pod"));

local gd = function (o, k, d) if std.objectHas(o, k) then o[k] else d;
local mko = function (a) std.foldl(function (i, j) i + j, a, {});

local cm_volumes = mko([
  {[i.name]: i.configMap.name}
  for i in k8s_pod.spec.volumes if std.objectHas(i, "configMap")
]);

local ed_volumes = mko([
  {[i.name]: i.emptyDir}
  for i in k8s_pod.spec.volumes if std.objectHas(i, "emptyDir")
]);

local env_overloads = {
};

local task_config_extra = {}
+ (
  if std.extVar("host_container") != "" then
  {
    "network_mode": "container:" + std.extVar("host_container"),
  }
  else
  {}
);

{
  "Job": {
    "ID": k8s_pod.metadata.name,
    "Name": k8s_pod.metadata.name,
    "Type": "service",
    // "Priority": 50,
    "Datacenters": ["dc1"],
    "TaskGroups": [
      {
        "Name": "group1",
        "Count": 1,
        "Networks": [
          {
            "Mode": "host",
            "DynamicPorts": [
              {
                "Label": "%s--%s" % [k8s_container.name, k8s_port.name],
                "To": -1,
              }
              for k8s_container in k8s_pod.spec.containers
              for k8s_port in k8s_container.ports
            ],
          },
        ],
        "Services": [
            {
              "Name": "k8s--%s--%s--%s" % [
                k8s_namespace,
                # k8s_pod.metadata.name
                k8s_pod.metadata.labels["spark-role"],
                k8s_port.name,
              ],
              "PortLabel": "%s--%s" % [k8s_container.name, k8s_port.name],
            }
            for k8s_container in k8s_pod.spec.containers
            for k8s_port in k8s_container.ports
        ],
        "Tasks": [
          {
            "Name": k8s_container.name,
            "Driver": "docker",
            "User": "",
            "Config": {
              "image": k8s_container.image,
              "args": std.flattenArrays([
                if i == "--properties-file" then
                  [
                    "--conf", "spark.driver.host=${attr.unique.network.ip-address}",
                    "--conf", "spark.driver.port=${NOMAD_PORT_spark_kubernetes_driver__driver_rpc_port}",
                    "--conf", "spark.driver.blockManager.port=${NOMAD_PORT_spark_kubernetes_driver__blockmanager}",
                    i
                  ]
                else
                  [i]
                for i in k8s_container.args
              ]),
              "volumes":
              [
                "../alloc/cm/%s:%s:ro" % [vol.name, vol.mountPath]
                for vol in k8s_container.volumeMounts
                if std.objectHas(cm_volumes, vol.name)
              ]
              + [
                "../alloc/ed/%s:%s" % [vol.name, vol.mountPath]
                for vol in k8s_container.volumeMounts
                if std.objectHas(ed_volumes, vol.name)
              ]
              + [
                "/dev/null:/var/run/secrets/kubernetes.io/serviceaccount/token:ro",
                "/dev/null:/var/run/secrets/kubernetes.io/serviceaccount/ca.crt:ro",
              ],
            } + task_config_extra,
            "Env": {
            }
            + mko([
              {[i.name]: gd(env_overloads, i.name, i.value)}
              for i in k8s_container.env
              if std.objectHas(i, "value")
              && i.name != "SPARK_DRIVER_URL"
            ])
            + mko([
              {
                [i.name]:
                {
                  "status.podIP": "${attr.unique.network.ip-address}",
                }[i.valueFrom.fieldRef.fieldPath]
              }
              for i in k8s_container.env
              if std.objectHas(i, "valueFrom")
            ]),
            "Resources": {
              "CPU": MHZ_PER_CPU * std.parseInt(k8s_container.resources.requests.cpu),
              "MemoryMB":
                if std.endsWith(k8s_container.resources.requests.memory, "Mi") then
                  std.parseInt(std.strReplace(k8s_container.resources.requests.memory, "Mi", ""))
                else
                  std.assertEqual(0, 1)
            },
            "Templates": [] +
            (
              if k8s_pod.metadata.labels["spark-role"] == "executor" then
              [{
                "DestPath": "secrets/file.env",
                "ChangeMode": "noop",
                "EmbeddedTmpl": |||
                  {{ with service "k8s--%s--driver--driver-rpc-port|any" }}{{ with index . 0 }}
                  SPARK_DRIVER_URL=spark://CoarseGrainedScheduler@{{ .Address }}:{{ .Port }}
                  {{ end }}{{ end }}
                  SPARK_JAVA_OPT_1000=-Dspark.blockManager.port={{ env "NOMAD_PORT_spark_kubernetes_executor__blockmanager" }}
                ||| % [k8s_namespace],
                "Envvars": true,
              }]
              else
              []
            ),
            "Leader": true
          }
          for k8s_container in k8s_pod.spec.containers
        ] +
        [
          {
            "Name": "k8s-volumes",
            "Driver": "docker",
            "User": "",
            "Config": {
              "image": std.extVar("k8s_emul_image"),
              "command": "python",
              "args": ["k8s-volumes-emul.py"],
            } + task_config_extra,
            "Env": {
              "CONSUL_ADDR": std.extVar("consul_addr"),
              "CONSUL_KV2DIR_ROOT": "/alloc/cm",
              "EMPTY_DIRS": std.join(":", ["/alloc/ed/%s" % i for i in std.objectFields(ed_volumes)]),
            } + mko([
              {["CONSUL_KV2DIR_DIR_%s" % i]: "%s%s/%s" % [configmaps_consul_prefix, k8s_namespace, cm_volumes[i]]}
              for i in std.objectFields(cm_volumes)
            ]),
            "Resources": {
              "CPU": 500,
              "MemoryMB": 256,
              "Networks": [
                {
                  "Device": "",
                  "CIDR": "",
                  "IP": "",
                  "MBits": 10,
                  "DynamicPorts": [
                  ]
                }
              ]
            },
            "Leader": false
          }
        ],
        "RestartPolicy": {
          "Attempts": 1,
          "Delay": 5e9,
          "Mode": "fail",
        },
        "ReschedulePolicy": {
          "Attempts": 0,
          "Unlimited": false,
        },
        "EphemeralDisk": {
          "SizeMB": 120
        }
      },
    ],
  }
}
