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
  SPARK_DRIVER_URL: "spark://CoarseGrainedScheduler@127.0.0.1:7078"
};

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
        "Tasks": std.map(
          function(k8s_container)
          {
            "Name": k8s_container.name,
            "Driver": "docker",
            "User": "",
            "Config": {
              "image": k8s_container.image,
              "args": k8s_container.args,
              "network_mode": "container:tests_cluster_1",
              "port_map": std.map(
                function(k8s_port)
                {
                  [k8s_port.name]: k8s_port.containerPort,
                },
                k8s_container.ports
              ),
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
            },
            "Env": {
            }
            + mko([
              {[i.name]: gd(env_overloads, i.name, i.value)}
              for i in k8s_container.env
              if std.objectHas(i, "value")
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
              "CPU": 500,
              "MemoryMB": 2048,
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
            "Leader": true
          },
          k8s_pod.spec.containers
        ) +
        [
          {
            "Name": "k8s-volumes",
            "Driver": "docker",
            "User": "",
            "Config": {
              "image": std.extVar("k8s_emul_image"),
              "command": "python",
              "args": ["k8s-volumes-emul.py"],
              "network_mode": "container:tests_cluster_1"
            },
            "Env": {
              "CONSUL_ADDR": "http://cluster:8500",
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
          "Attempts": 0,
        },
        "ReschedulePolicy": {
          "Attempts": 0,
        },
        "EphemeralDisk": {
          "SizeMB": 120
        }
      },
    ],
  }
}
