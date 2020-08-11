import logging

from aiohttp import web as aw


async def get_health(request):
    return aw.Response(text="ok")


app = aw.Application()
logging.basicConfig(level=logging.DEBUG)
app.add_routes([
    aw.get('/health', get_health),
])

aw.run_app(app)
