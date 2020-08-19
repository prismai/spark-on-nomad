import asyncio
import base64
import os
import pathlib
import shutil

import aiohttp
import aiolimiter
import aiorun
import atomicwrites

from log import logger

CONSUL_ADDR = os.environ["CONSUL_ADDR"]

CONSUL_KV2DIR_ROOT = os.environ["CONSUL_KV2DIR_ROOT"]
PREFIX = "CONSUL_KV2DIR_DIR_"


async def dir_task(limiter, session, path, consul_path):
    path.mkdir(exist_ok=True)

    prev_items = {str(i.relative_to(path)) for i in path.rglob("*")}

    index = 0

    while True:
        if index:
            index_q = f"&index={index}"
        else:
            index_q = ""

        logger.debug("dir_task: get: path=%s index=%s ...", consul_path, index)

        try:
            await limiter.acquire()
            async with session.get(
                f"{CONSUL_ADDR}/v1/kv/{consul_path}?recurse=true{index_q}",
            ) as r:
                logger.debug("dir_task: ... get: path=%s status=%s", consul_path, r.status)

                new_index = int(r.headers["X-Consul-Index"])
                if new_index < index:
                    index = 0
                    logger.warning("dir_task: path=%s: resetting index", consul_path)
                else:
                    index = new_index

                if r.status != 200:
                    continue

                j = await r.json()
        except (
            aiohttp.client_exceptions.ClientConnectorError,
            aiohttp.client_exceptions.ServerDisconnectedError,
            asyncio.exceptions.TimeoutError,
        ) as e:
            logger.warning("dir_task: consul server: %s", e)
            continue

        items = {i["Key"][len(consul_path) + 1:]: base64.b64decode(i["Value"]) for i in j}

        for k, v in items.items():
            logger.debug("dir_task: path=%s: writing '%s'", consul_path, k)

            fpath = path / k

            with atomicwrites.atomic_write(fpath, mode="wb", overwrite=True) as f:
                f.write(v)

            fpath.chmod(0o444)

            prev_items.discard(k)

        for i in prev_items:
            logger.debug("dir_task: path=%s: deleting '%s'", consul_path, i)
            path.joinpath(i).unlink()

        prev_items = set(items)


async def main():
    for i in os.environ.get("EMPTY_DIRS", "").split(":"):
        if not i:
            continue

        p = pathlib.Path(i)
        p.mkdir(parents=True, exist_ok=True)
        p.chmod(0o777)

    dirs = {
        k[len(PREFIX):]: v
        for k, v in os.environ.items()
        if k.startswith(PREFIX)
    }

    root = pathlib.Path(CONSUL_KV2DIR_ROOT)
    root.mkdir(parents=True, exist_ok=True)

    for i in root.iterdir():
        if i.is_dir():
            if i.name not in dirs:
                logger.debug("removing unmanaged directory: %s", i)
                shutil.rmtree(i)
        else:
            logger.debug("removing unmanaged: %s", i)
            i.unlink()

    limiter = aiolimiter.AsyncLimiter(2, 1)  # max p1 requests per p2 seconds

    async with aiohttp.ClientSession() as session:
        await asyncio.gather(
            *(
                dir_task(
                    limiter,
                    session,
                    root / k,
                    v,
                )
                for k, v in dirs.items()
            )
        )


aiorun.run(main(), stop_on_unhandled_errors=True)
