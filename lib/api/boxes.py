from pathlib import Path
from uuid import UUID
from hashlib import sha256

from ..config import BOX_PACKAGES

AllBoxes = []


class BoxTarball:
    def __init__(self, file: Path):
        self.file = file
        self.hash = None
        self.config_hashes = {}
        self.build()

    def build(self):
        # generate templates with box variables
        pass

    def _set_hash(self):
        with open(self.file, 'rb') as tarball:
            self.hash = sha256(tarball.read())


class Box:
    def __init__(self, uuid: UUID, key: str, versions: dict):
        self.uuid = uuid
        self.key_hash = key
        self.versions = versions  # package => {is => version, tgt => version}
        self.tarball = None
        self.packages = {}  # is, available, target
        # is = 'apt list --installed'
        self.hardware = {}
        self.platform = None  # physical, virtual, container; container will need ulogd2 for nftables logging

    def config_up_to_date(self) -> bool:
        # todo: tarball/config hash comparison
        return True

    def pkgs_up_to_date(self):
        for pkg in BOX_PACKAGES:
            if self.packages['is'][pkg] != self.packages['target'][pkg]:
                return False

        return True


def get_box(uuid: str) -> Box:
    for box in AllBoxes:
        if box.uuid == uuid:
            return box


# register
#   python3 -c "from uuid import uuid4; print(f'{uuid4()}.box.shieldwall')"
