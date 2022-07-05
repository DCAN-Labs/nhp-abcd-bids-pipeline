import os

# load the version
THISDIR = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(THISDIR, "VERSION")) as f:
    __version__ = f.readline().strip()
