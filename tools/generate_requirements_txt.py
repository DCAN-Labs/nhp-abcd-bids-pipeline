#!/usr/bin/env python3
from os.path import abspath, dirname, join
from datetime import datetime
import toml

PROJECTDIR = dirname(abspath(dirname(__file__)))

pyproject_file = join(PROJECTDIR, "pyproject.toml")
requirements_file = join(PROJECTDIR, "requirements.txt")


if __name__ == "__main__":
    # load config
    config = toml.load(pyproject_file)

    # get dependencies
    requirements = config["project"]["dependencies"]
    requirements += [""]
    requirements += config["project"]["optional-dependencies"]["dev"]

    with open(requirements_file, "w") as f:
        f.write("# Auto-generated on %s\n" % datetime.now().isoformat())
        for r in requirements:
            f.write("%s\n" % r)
