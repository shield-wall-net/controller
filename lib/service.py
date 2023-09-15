import signal
from time import sleep

from traceback import format_exc
from debug import log


class Service:
    def __init__(self):
        signal.signal(signal.SIGUSR1, self.reload)
        signal.signal(signal.SIGINT, self.stop)

    def reload(self):
        log('Reloading service')

    def stop(self):
        raise SystemExit("Stopped service!")

    def run(self):
        try:
            while True:
                sleep(10)

        except (ValueError, KeyError, SyntaxError, SystemExit, IndexError, FileNotFoundError,
                OSError) as err:
            log(f"Got error: {err}")
            log(format_exc())
            self.stop()
