import argparse
import contextlib
import sys
import time
import os
import enum
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import subprocess
from typing import Generator, List, Dict, Optional, Tuple
import functools


BUILDS_FOLDER = Path(__file__).parent / "builds"
BUILDS_FOLDER.mkdir(parents=True, exist_ok=True)


class Installer(enum.Enum):
    APK = "apk"
    APT = "apt-get"
    NONE = "NONE"


@dataclass(frozen=True, eq=True)
class BuildDesc:
    arch: str
    interperter: str
    version: str
    luajit: str
    compile_details: str
    image_name: str

    def path(self, base_path: Path = BUILDS_FOLDER) -> Path:
        return (
            base_path
            / self.version
            / f"{self.arch}-{self.interperter}"
            / self.image_name
        )


class Registry:
    data: List[BuildDesc]

    def __init__(self) -> None:
        self.data = []

    def add(self, desc: BuildDesc):
        if desc in self.data:
            return

        print("Build path saved", desc.path())
        self.data.append(desc)
        self.save()

    def find(self, desc: BuildDesc) -> Optional[BuildDesc]:
        values = [e for e in self.data if e.image_name == desc.image_name]
        if values:
            return values[0]
        values = [
            e
            for e in self.data
            if e.arch == desc.arch and e.interperter == desc.interperter
        ]
        if values:
            return values[0]
        return None

    def list(self):
        seen_versions = set()
        if not self.data:
            print("No existing builds found")
            return
        print("Images found:")
        for desc in self.data:
            version_str = f"v{desc.version} / {desc.arch} {desc.interperter}"
            if version_str not in seen_versions:
                seen_versions.add(version_str)

            print(f" - {desc.image_name} ({version_str})")

        print("Archs found:")
        for version in seen_versions:
            print(" - " + version)

    @property
    def filepath(self) -> Path:
        return BUILDS_FOLDER / "data.json"

    def clear(self):
        self.filepath.unlink(missing_ok=True)

    def load(self):
        location = self.filepath
        if not location.exists():
            return

        with open(location) as fp:
            res = json.load(fp)
            self.data = [BuildDesc(**d) for d in res["data"]]

    def save(self):
        with open(self.filepath, "w") as fp:
            json.dump({"data": [asdict(d) for d in self.data]}, fp)


def _run(args: List[str]) -> Tuple[int, str]:
    response = subprocess.run(args, stdout=subprocess.PIPE)
    output = response.stdout.decode("utf-8")
    return response.returncode, output


@dataclass
class SysInfo:
    user: str
    arch: str
    envs: Dict[str, str]
    install_system: Installer
    ld_musl_aarch64: bool
    installed: Dict[str, bool]

    def home(self) -> str:
        return self.envs["HOME"]


@dataclass
class DockerSummary:
    id: str
    names: str
    image: str
    ports: str
    payload: Dict
    _sys_info: Optional[SysInfo] = None
    _skip_installs: str = ""

    def __hash__(self) -> int:
        return id(self)

    @classmethod
    def from_json_string(cls, value: str) -> "DockerSummary":
        data = json.loads(value)
        return cls(
            id=data["ID"],
            names=data["Names"],
            image=data["Image"],
            ports=data["Ports"],
            payload=data,
        )

    @contextlib.contextmanager
    def _ensure_copy_wather_process(self) -> Generator[None, None, None]:
        """
        Ensure that the copy watcher process is running.
        """
        command = [sys.executable, __file__, "copy", "-n", self.id]
        if not subprocess.run(["pgrep", "-f", " ".join(command)]).returncode:
            print("Copy watcher already running")
            yield None
            return None

        print("Starting copy watcher")
        copy_p = subprocess.Popen(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        yield None
        if copy_p.poll() is None:
            print("Killing copy watcher")
            copy_p.terminate()

    def enter(self):
        with self._ensure_copy_wather_process():
            try:
                subprocess.check_call(
                    [
                        "docker",
                        "exec",
                        "-it",
                        self.id,
                        "bash" if self.system_info().installed["bash"] else "sh",
                    ]
                )
            except subprocess.CalledProcessError as err:
                if err.returncode in (130, 127):
                    print("Safely exited")
                    return
                raise

    def exec(self, command: str | List[str], workingdir: str = "") -> Tuple[int, str]:
        if isinstance(command, str):
            command = [command]
        code, result = _run(
            [
                "docker",
                "exec",
                *(["-w", workingdir] if workingdir else []),
                self.id,
                *command,
            ]
        )
        return code, result.strip()

    def file_exists(self, path: str, is_dir: bool = False):
        code, _ = self.exec(["test", "-d" if is_dir else "-f", path])
        return code == 0

    def copy(self, to_docker: bool, from_path: str, to_path: str):
        args = [
            "docker",
            "cp",
            from_path,
            to_path,
        ]
        value = args[3 if to_docker else 2]
        args[3 if to_docker else 2] = self.id + ":" + value
        print(args)
        _run(args)

    def system_info(self) -> SysInfo:
        if self._sys_info:
            return self._sys_info
        _, arch = self.exec(["uname", "-m"])
        _, user = self.exec("whoami")
        install_system = Installer.NONE
        has_apt = self.exec(["which", "apt-get"])[0] == 0
        has_apk = self.exec(["which", "apk"])[0] == 0

        if has_apt:
            install_system = Installer.APT
        if has_apk:
            install_system = Installer.APK

        interperter = self.exec(
            [
                "ls",
                "/lib",
            ]
        )[1].splitlines()

        installed = {
            key: self.exec(["which", key])[0] == 0
            for key in ["python3", "npm", "node", "nvim", "bash", "sh"]
        }

        envs = {
            line.split("=")[0]: line.split("=")[1].strip()
            for line in self.exec(["printenv"])[1].splitlines()
        }

        sys_info = SysInfo(
            user=user,
            arch=arch,
            install_system=install_system,
            ld_musl_aarch64="ld-linux-aarch64.so.1" in interperter,
            installed=installed,
            envs=envs,
        )
        self._sys_info = sys_info
        return sys_info

    @functools.cache
    def install_setup(self):
        print("install setup")
        if self.system_info().install_system == Installer.APT:
            code, res = self.exec(["apt-get", "update", "--fix-missing"])
            if code:
                print(res)
                raise RuntimeError("Failed")
            self.exec(["apt-get", "install", "-y", "apt-utils"])
            return

        self.exec(["apk", "update"])

    def link_nvim(self):
        print("Link NVIM")
        self.exec(
            [
                "ln",
                "-sf",
                self.system_info().home() + "/neovim/build/bin/nvim",
                "/bin/nvim",
            ]
        )
        code, result = self.exec(["nvim", "--version"])
        print("NVIM installed", code, result)

    def sync_config(self, overwrite: bool = True):
        sys_info = self.system_info()
        local_home = os.environ["HOME"]
        config_folder = sys_info.home() + "/.config"
        self.exec(["mkdir", "-p", config_folder])
        self.exec(["mkdir", "-p", sys_info.home() + "/.local/share/nvim"])
        if not overwrite and self.file_exists(config_folder + "/nvim", is_dir=True):
            return

        print("Removing .config/nvim")
        self.exec(["rm", "-rf", config_folder + "/nvim"])
        print("Remove .local/share/nvim")
        self.exec(["rm", "-rf", sys_info.home() + "/.local/share/nvim"])
        print("Syncing .config/nvim")
        self.copy(
            to_docker=True,
            from_path=local_home + "/.config/nvim",
            to_path=config_folder,
        )
        print("Syncing .config/github-copilot")
        self.copy(
            to_docker=True,
            from_path=local_home + "/.config/github-copilot",
            to_path=config_folder,
        )
        return

    def set_skips(self, skips: str):
        self._skip_installs = skips

    def install(self, packages: List[str], lean: bool = False):
        self.install_setup()
        sys_info = self.system_info()
        install_system = sys_info.install_system
        packages = [e for e in packages if e not in self._skip_installs.split(",")]

        command = (
            [
                "apt-get",
                "install",
                "-y",
            ]
            if install_system == Installer.APT
            else ["apk", "add"]
        )
        if lean and install_system == "apt-get":
            command.append("--no-install-recommends")

        print("  installing  (this can take a while)... ", packages)
        code, output = self.exec(command + packages)
        print("  installed ", packages)
        if code != 0:
            raise RuntimeError(f"Intall failed {packages}: {output=}")

    def ensure_deps(self):
        self.install_setup()
        self.install(
            [
                "wget",
                "git",
                "ripgrep",
            ]
        )
        sys_info = self.system_info()

        if not sys_info.installed["node"]:
            self.install(["nodejs", "npm"], lean=True)

        if not sys_info.installed["python3"]:
            self.install(["python3"])

    def build_neovim(self, version: str = "stable", overwrite=False):
        sys_info = self.system_info()
        if not overwrite and sys_info.installed["nvim"]:
            return
        if sys_info.install_system == Installer.APK:
            self.install(["build-base", "coreutils", "unzip", "gettext-tiny-dev"])
        self.install(
            [
                "gcc",
                "g++",
                "curl",
                "unzip",
                "make",
                "gettext",
                "cmake",
                "libtool",
            ]
        )
        zip_location = "/tmp/neovim.zip"
        if not self.file_exists(zip_location, is_dir=False):
            print(f"Downloading Neovim {version=}")
            code, _ = self.exec(
                [
                    "curl",
                    "-L",
                    "-o",
                    zip_location,
                    f"https://github.com/neovim/neovim/archive/refs/tags/{version}.zip",
                ]
            )

        if not self.file_exists(f"/tmp/neovim-{version}", is_dir=True):
            code, _ = self.exec(["unzip", "-oq", zip_location, "-d", "/tmp/"])
            if code != 0:
                raise RuntimeError("Unzip failed")

        home = sys_info.home()
        neovim_dir = home + "/neovim"
        self.exec(["rm", "-rf", neovim_dir])
        code, _ = self.exec(["mv", f"/tmp/neovim-{version}", neovim_dir])
        if code != 0:
            raise RuntimeError("Unzip failed")
        self.exec(["rm", "-rf", neovim_dir + "/build"])
        code, res = self.exec(
            [
                "make",
                f'CMAKE_EXTRA_FLAGS="-DCMAKE_INSTALL_PREFIX={neovim_dir}"',
            ],
            workingdir=neovim_dir,
        )
        if code != 0:
            print(res)
            raise RuntimeError("Make failed")
        code, res = self.exec(
            [
                "make",
                "install",
            ],
            workingdir=neovim_dir,
        )
        if code != 0:
            print(res)
            raise RuntimeError("Make 2 failed")

    def nvim_version(self):
        code, res = self.exec(["nvim", "--version"])
        if code:
            raise RuntimeError("nvim not found")

        version, _, luajit, compile_details = res.splitlines()[:4]

        return {
            "version": version.split("v")[1].strip(),
            "luajit": luajit.split(" ")[1].strip(),
            "compile_details": compile_details,
        }

    def store_build(self, local_destination: Path):
        sys_info = self.system_info()
        from_path = sys_info.home() + "/neovim/"
        if not self.file_exists(from_path, is_dir=True):
            raise ValueError("Nvim not found:" + from_path)

        local_destination.mkdir(parents=True, exist_ok=True)
        self.copy(
            to_docker=False,
            to_path=str(local_destination),
            from_path=from_path,
        )

    def load_build(self, local_destination: Path):
        sys_info = self.system_info()
        docker_path = sys_info.home()
        local_destination = local_destination / "neovim"
        local_destination.mkdir(parents=True, exist_ok=True)
        self.copy(
            to_docker=True,
            from_path=str(local_destination),
            to_path=docker_path,
        )


class Docker:
    @staticmethod
    def ps(name: str | None = None) -> List[DockerSummary]:
        _, data = _run(["docker", "ps", "--format", "json"])
        results = [DockerSummary.from_json_string(row) for row in data.splitlines()]
        if name:
            results = [e for e in results if name in e.names]
        return results


def _get_docker_process(container_name: str) -> Optional[DockerSummary]:
    processes = Docker.ps()
    if not container_name:
        print("Pick a conatiner")
        for i, p in enumerate(processes):
            print(i, "  ", p.names)
        container_name = input("\n")

    processes = [
        pro
        for i, pro in enumerate(processes)
        if container_name in pro.names or str(i) == container_name
    ]
    if len(processes) != 1:
        print("Couldn't find unique container ", container_name)
        print([p.names for p in processes])
        return None
    docker = processes[0]
    return docker


def enter_docker() -> None:
    args = parser.parse_args()
    docker = _get_docker_process(args.name)
    if not docker:
        return
    docker.enter()


def run_dnvim() -> None:
    args = parser.parse_args()
    registry = Registry()
    registry.load()
    container_name = args.container_name or args.name
    docker = _get_docker_process(container_name)
    if not docker:
        return
    docker.set_skips(args.skip_deps or "")
    docker.ensure_deps()
    docker.sync_config(overwrite=args.sync_config)
    info = docker.system_info()
    if not args.build and not info.installed["nvim"]:
        desc = registry.find(
            BuildDesc(
                arch=info.arch,
                interperter="ld_musl_aarch64" if info.ld_musl_aarch64 else "",
                image_name=docker.names,
                version="",
                luajit="",
                compile_details="",
            )
        )
        if not desc:
            raise RuntimeError("Nvim is not installed and not build match: use -b")

        docker.load_build(desc.path(BUILDS_FOLDER))
        docker.link_nvim()

    if args.build:
        docker.build_neovim()

    if args.build or args.store:
        version = docker.nvim_version()
        build_desc = BuildDesc(
            arch=info.arch,
            version=version["version"],
            luajit=version["luajit"],
            compile_details=version["compile_details"],
            interperter="ld_musl_aarch64" if info.ld_musl_aarch64 else "",
            image_name=docker.names,
        )
        docker.store_build(build_desc.path(BUILDS_FOLDER))
        registry.add(build_desc)
        registry.list()

    if args.store:
        return
    docker.link_nvim()
    docker.enter()


def run_list():
    registry = Registry()
    registry.load()
    print("The following built nvim caches exist locally")
    print("")
    registry.list()


def _run_copy() -> None:
    """Watch the file /tmp/copy.txt for changes and run pbcopy on the contents."""
    file_path = Path("/tmp/copy.txt")
    # ensure the file file_exists
    file_path.touch(exist_ok=True)
    last_change = file_path.stat().st_mtime
    while True:
        if file_path.stat().st_mtime != last_change:
            last_change = file_path.stat().st_mtime
            with open(file_path, "r") as fp:
                value = fp.read().strip()
                print("contents changed")
                print(value)
                print("-" * 10)
                subprocess.run(["pbcopy"], input=value.encode("utf-8"))
        time.sleep(0.5)


def _run_docker_copy(container_id: str) -> None:
    """exec against a running docker checking for changes in /tmp/copy.txt and running pbcopy."""
    container = next((cont for cont in Docker.ps() if cont.id == container_id), None)
    if not container:
        return
    print("Listening for changes in /tmp/copy.txt")
    last_change = 0
    while True:
        time.sleep(0.5)

        exit_code, content = container.exec(
            ["stat", "--format", "'%Y'", "/tmp/copy.txt"]
        )
        if exit_code != 0:
            continue
        this_change = int(content.strip("'"))
        if last_change == this_change:
            continue
        last_change = this_change
        if last_change == 0:
            continue
        exit_code, content = container.exec(["cat", "/tmp/copy.txt"])
        if exit_code != 0:
            continue
        subprocess.run(["pbcopy"], input=content.encode("utf-8"))
        print("Copied to clipboard")
        print(content)
        print("-" * 10)


def run_copy() -> None:
    args = parser.parse_args()
    container_id = args.name
    if not container_id:
        return _run_copy()
    _run_docker_copy(container_id)


def main() -> None:
    args = parser.parse_args()
    container_name = args.container_name
    if container_name == "copy":
        run_copy()
        return exit(0)

    if container_name == "list":
        run_list()
        return exit(0)

    if container_name == "enter":
        enter_docker()
        return exit(0)

    run_dnvim()
    exit(0)


parser = argparse.ArgumentParser(
    prog="dvnim",
    description="Handle creating Neovim setup within Docker Containers",
)
parser.add_argument(
    "container_name",
    help="Container Name or named_action (list, )",
    default="",
    nargs="?",
)
parser.add_argument("--sync-config", action="store_true")
parser.add_argument("-b", "--build", action="store_true")
parser.add_argument("-s", "--store", action="store_true")
parser.add_argument(
    "-n", "--name", help="Docker name if not provided as the first arg", default=""
)
parser.add_argument("--skip-deps", default="")

if __name__ == "__main__":
    main()
