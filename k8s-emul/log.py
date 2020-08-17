import logging


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


logging.setLoggerClass(LazyLogger)
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger("main")
