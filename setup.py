#!/usr/bin/env python3
import os
import sys
import site
import setuptools

# get the project directory
PROJECT_DIR = os.path.abspath(os.path.dirname(__file__))

# get the version
with open(os.path.join(PROJECT_DIR, "nhp_abcd", "VERSION")) as f:
    __version__ = f.readline().strip()

# This line enables user based installation when using pip in editable mode with the latest
# pyproject.toml config
site.ENABLE_USER_SITE = "--user" in sys.argv[1:]

# get scripts path
SCRIPTSPATH = os.path.join(PROJECT_DIR, "nhp_abcd", "scripts")

if __name__ == "__main__":
    # setup entry points scripts
    entry_points = {
        "console_scripts": [
            "nhp_abcd_{0}=nhp_abcd.scripts.{0}:main".format(f.split(".")[0])
            for f in os.listdir(SCRIPTSPATH)
            if not ("__pycache__" in f or "__init__.py" in f or ".DS_Store" in f)
        ]
    }

    # create setup options
    setup_options = {"entry_points": entry_points, "version": __version__}

    # run setup
    setuptools.setup(**setup_options)
