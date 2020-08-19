import asyncio
import io
import json
import os

import _jsonnet
import aiohttp
import ruamel.yaml
from aiohttp import web as aw
from aiojobs import aiohttp as aj

from log import logger


CONFIGMAPS_CONSUL_PREFIX = os.environ["CONFIGMAPS_CONSUL_PREFIX"]
CONSUL_ADDR = os.environ["CONSUL_ADDR"]
NOMAD_ADDR = os.environ["NOMAD_ADDR"]
K8S_EMUL_IMAGE = os.environ["K8S_EMUL_IMAGE"]


def yaml_dump(d):
    yaml = ruamel.yaml.YAML()
    s = io.StringIO()
    yaml.dump(d, stream=s)
    return s.getvalue()


def dbg_yaml(d):
    def cb():
        return yaml_dump(d)

    return cb


def dbg_jsons2yaml(s):
    def cb():
        return yaml_dump(json.loads(s))

    return cb


def get_client_session(request):
    return request.app["client_session"]


async def get_health(request):
    logger.debug("get_health %s", lambda: 42)
    return aw.Response(text="ok")


async def get_pods(request):
    # request.match_info["namespace"]

    if request.query.get("watch", "false") == "true":
        ws = aw.WebSocketResponse()
        await ws.prepare(request)

        async for msg in ws:
            if msg.type == aw.WSMsgType.text:
                pass
                # j = msg.json()
            elif msg.type == aw.WSMsgType.close:
                break

        return ws


async def post_pods(request):
    k8s_pod_spec = await request.text()
    namespace = request.match_info["namespace"]
    logger.debug(
        "post_pods namespace=%s\n%s",
        namespace,
        dbg_jsons2yaml(k8s_pod_spec),
    )
    nomad_job_spec = _jsonnet.evaluate_file(
        "k8s-pod-to-nomad-job.jsonnet",
        ext_vars=dict(
            configmaps_consul_prefix=CONFIGMAPS_CONSUL_PREFIX,
            k8s_namespace=namespace,
            k8s_pod=k8s_pod_spec,
            k8s_emul_image=K8S_EMUL_IMAGE,
        ),
    )
    logger.debug(
        "post_pods nomad job: \n%s",
        dbg_jsons2yaml(nomad_job_spec),
    )

    async with get_client_session(request).post(
        f"{NOMAD_ADDR}/v1/jobs",
        data=nomad_job_spec.encode(),
    ) as resp:
        logger.debug("post_pods nomad code=%s", resp.status)
        nomad_job_result = await resp.text()
        if 200 <= resp.status < 300:
            logger.debug("post_pods nomad resp:\n%s", dbg_jsons2yaml(nomad_job_result))

            reply = _jsonnet.evaluate_file(
                "k8s-pod-create-result.jsonnet",
                ext_vars=dict(
                    k8s_namespace=namespace,
                    k8s_pod=k8s_pod_spec,
                    nomad_job_result=nomad_job_result,
                ),
            )

            logger.debug("post_pods replying:\n%s", dbg_jsons2yaml(reply))

            return aw.json_response(
                reply,
                status=201,
                dumps=lambda x: x,
            )
        else:
            logger.debug("post_pods nomad resp: %s", nomad_job_result)
            return aw.Response(
                text="Failed",
                status=400,
            )


async def get_pod(request):
    namespace = request.match_info["namespace"]
    name = request.match_info["name"]
    logger.debug("get_pod namespace=%s name=%s", namespace, name)

    client_session = get_client_session(request)

    async with client_session.get(f"{NOMAD_ADDR}/v1/jobs?prefix={name}") as resp:
        if resp.status != 200:
            logger.debug("get_pod: nomad response code=%s: %s", resp.status, await resp.text())
            return aw.Response(
                text="Failed",
                status=400,
            )
        else:
            jobs = await resp.json()
            jobs = [i for i in jobs if i["Name"] == name]
            if jobs:
                reply = _jsonnet.evaluate_file(
                    "k8s-pod-get-result.jsonnet",
                    ext_vars=dict(
                        k8s_namespace=namespace,
                        nomad_job=json.dumps(jobs[0]),
                    ),
                )
                logger.debug("get_pod replying:\n%s", dbg_jsons2yaml(reply))

                return aw.json_response(
                    reply,
                    status=200,
                    dumps=lambda x: x,
                )
            else:
                logger.debug("get_pod replying -- not found")
                return aw.Response(
                    text="Not found",
                    status=404,
                )


async def post_services(request):
    k8s_service_spec = await request.text()
    namespace = request.match_info["namespace"]
    logger.debug(
        "post_services namespace=%s\n%s",
        namespace,
        dbg_jsons2yaml(k8s_service_spec),
    )
    # reply = _jsonnet.evaluate_file(
    #     "k8s-pod-create-result.jsonnet",
    #     ext_vars=dict(
    #         k8s_namespace=namespace,
    #         k8s_pod=k8s_pod_spec,
    #         nomad_job_result=nomad_job_result,
    #     ),
    # )
    reply = "{}"

    logger.debug("post_services replying:\n%s", dbg_jsons2yaml(reply))

    return aw.json_response(
        reply,
        status=201,
        dumps=lambda x: x,
    )


async def post_configmaps(request):
    k8s_configmap_spec = await request.json()
    namespace = request.match_info["namespace"]
    logger.debug(
        "post_configmaps namespace=%s\n%s",
        namespace,
        dbg_yaml(k8s_configmap_spec),
    )

    k8s_configmap_data = k8s_configmap_spec["data"]

    client_session = get_client_session(request)
    consul_url_prefix = f"{CONSUL_ADDR}/v1/kv/{CONFIGMAPS_CONSUL_PREFIX}{namespace}/{k8s_configmap_spec['metadata']['name']}/"  # noqa: E501

    consul_responses = await asyncio.gather(
        *(
            client_session.put(
                f"{consul_url_prefix}{k}",
                data=v.encode(),
            )
            for k, v in k8s_configmap_data.items()
        )
    )

    failed = False

    for resp, k in zip(consul_responses, k8s_configmap_data):
        if 200 <= resp.status < 300:
            if not await resp.json():
                logger.debug("post_configmaps consul put failed for %s%s", consul_url_prefix, k)
                failed = True
        else:
            logger.debug("post_configmaps consul put failed for %s%s code=%s", consul_url_prefix, k, resp.status)
            failed = True

    if failed:
        return aw.Response(
            text="Failed",
            status=500,
        )

    reply = "{}"

    logger.debug("post_configmap replying:\n%s", dbg_jsons2yaml(reply))

    return aw.json_response(
        reply,
        status=201,
        dumps=lambda x: x,
    )


async def on_startup(app):
    app["client_session"] = aiohttp.ClientSession()


async def on_cleanup(app):
    app["client_session"].close()


app = aw.Application()
aj.setup(app)
app.on_startup.append(on_startup)
app.on_cleanup.append(on_cleanup)
app.add_routes([
    aw.get("/health", get_health),
    aw.post("/api/v1/namespaces/{namespace}/services", post_services),
    aw.post("/api/v1/namespaces/{namespace}/configmaps", post_configmaps),
])

r = app.router.add_resource("/api/v1/namespaces/{namespace}/pods")
r.add_route("GET", get_pods)
r.add_route("POST", post_pods)

r = app.router.add_resource("/api/v1/namespaces/{namespace}/pods/{name}")
r.add_route("GET", get_pod)
# r.add_route("DELETE", delete_pod)
#
# r = app.router.add_resource("/api/v1/namespaces/{namespace}/services/{name}")
# r.add_route("GET", get_service)
# r.add_route("DELETE", delete_service)

aw.run_app(app)
