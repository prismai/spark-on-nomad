import json
import logging
import os

import _jsonnet
import aiohttp
import ruamel.yaml as yaml
from aiohttp import web as aw
from aiojobs import aiohttp as aj


NOMAD_ADDR = os.environ["NOMAD_ADDR"]


class LazyLogger(logging.getLoggerClass()):
    def _log(self, level, msg, args, **kwargs):
        def maybe_callable(x):
            return x() if callable(x) else x

        super()._log(
            level,
            maybe_callable(msg),
            tuple(maybe_callable(i) for i in args),
            **kwargs
        )


def dbg_json2yaml(s):
    def cb():
        return yaml.dump(json.loads(s))

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
        dbg_json2yaml(k8s_pod_spec),
    )
    nomad_job_spec = _jsonnet.evaluate_file(
        "k8s-pod-to-nomad-job.jsonnet",
        ext_vars=dict(
            k8s_namespace=namespace,
            k8s_pod=k8s_pod_spec,
        ),
    )
    logger.debug(
        "post_pods nomad job: \n%s",
        dbg_json2yaml(nomad_job_spec),
    )

    async with get_client_session(request).post(
        f"{NOMAD_ADDR}/v1/jobs",
        data=nomad_job_spec.encode(),
    ) as resp:
        logger.debug("post_pods nomad code=%s", resp.status)
        nomad_job_result = await resp.text()
        if 200 <= resp.status < 300:
            logger.debug("post_pods nomad resp:\n%s", dbg_json2yaml(nomad_job_result))

            reply = _jsonnet.evaluate_file(
                "k8s-pod-create-result.jsonnet",
                ext_vars=dict(
                    k8s_namespace=namespace,
                    k8s_pod=k8s_pod_spec,
                    nomad_job_result=nomad_job_result,
                ),
            )

            logger.debug("post_pods replying:\n%s", dbg_json2yaml(reply))

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


async def on_startup(app):
    app["client_session"] = aiohttp.ClientSession()


async def on_cleanup(app):
    app["client_session"].close()


logging.setLoggerClass(LazyLogger)
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

app = aw.Application()
aj.setup(app)
app.on_startup.append(on_startup)
app.on_cleanup.append(on_cleanup)
app.add_routes([
    aw.get("/health", get_health),
    # aw.post("/api/v1/namespaces/{namespace}/services", post_services),
])

r = app.router.add_resource("/api/v1/namespaces/{namespace}/pods")
r.add_route("GET", get_pods)
r.add_route("POST", post_pods)

# r = app.router.add_resource("/api/v1/namespaces/{namespace}/pods/{name}")
# r.add_route("GET", get_pod)
# r.add_route("DELETE", delete_pod)
#
# r = app.router.add_resource("/api/v1/namespaces/{namespace}/services/{name}")
# r.add_route("GET", get_service)
# r.add_route("DELETE", delete_service)

aw.run_app(app)
