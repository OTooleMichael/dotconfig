import argparse
import os
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import subprocess
from typing import List, Dict, Optional, Tuple
import functools

BUILDS_FOLDER = Path(__file__).parent / "builds"
BUILDS_FOLDER.mkdir(parents=True, exist_ok=True)


@dataclass(frozen=True, eq=True)
class BuildDesc:
    arch: str
    interperter: str
    version: str
    luajit: str
    compile_details: str
    image_name: str

    def path(self, base_path: Path = BUILDS_FOLDER) -> Path:
        return base_path / self.version / f"{self.arch}-{self.interperter}" / self.image_name


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
            e for e in self.data 
            if e.arch == desc.arch and e.interperter == desc.interperter
        ] 
        if values:
            return values[0]
        return None

    def list(self):
        seen_versions = set()
        for desc in self.data:
            version_str = f"v{desc.version} / {desc.arch} {desc.interperter}"
            if version_str not in seen_versions:
                print(version_str)
                seen_versions.add(version_str)

            print(" image " + desc.image_name)

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
            self.data = [
                BuildDesc(**d) for d in res["data"]
            ]

    def save(self):
        with open(self.filepath, "w") as fp:
            json.dump({
                "data": [asdict(d) for d in self.data]
            }, fp)


def _run(args: List[str]) -> Tuple[int, str]:
    response = subprocess.run(args, stdout=subprocess.PIPE)
    output = response.stdout.decode("utf-8")
    return response.returncode, output


@dataclass
class SysInfo:
    user: str
    arch: str
    envs: Dict[str, str]
    install_system: str
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

    def docker_enter(self):
        try:
            subprocess.check_call([
                "docker", "exec",
                "-it",
                self.id,
                "bash" if self.system_info().installed["bash"] else "sh",
            ])
        except subprocess.CalledProcessError as err:
            if err.returncode == 130:
                print("Safely exited")
                return
            raise

    def exec(self, command: str | List[str], workingdir: str = "") -> Tuple[int, str]:
        if isinstance(command, str):
            command = [command]
        code, result =  _run([
            "docker", 
            "exec",
            *(["-w", workingdir] if workingdir else []),
            self.id,
            *command,
        ])
        return code, result.strip()

    def file_exists(self, path: str, is_dir: bool = False):
        code, _ = self.exec(["test","-d" if is_dir else "-f", path])
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
        _run(args)

    def system_info(self) -> SysInfo:
        if self._sys_info:
            return self._sys_info
        _, arch = self.exec(["uname","-m"])
        _, user = self.exec("whoami")
        install_system = ""
        has_apt = self.exec(["which", "apt-get"])[0] == 0
        has_apk = self.exec(["which", "apk"])[0] == 0

        if has_apt:
            install_system = "apt-get"
        if has_apk:
            install_system = "apk"

        interperter = self.exec([
            "ls", "/lib",
        ])[1].splitlines()

        installed = {
            key: self.exec(["which", key])[0] == 0
            for key in ["python3", "npm", "node", "nvim", "bash", "sh"]
        }

        envs = {
            line.split("=")[0]: line.split('=')[1].strip()
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
        if self.system_info().install_system == "apt-get":
            code, res = self.exec(["apt-get", "update", "--fix-missing"])
            if code:
                print(res)
                raise RuntimeError("Failed")
            self.exec(["apt-get","install", "-y", "apt-utils"])
            return
        self.exec(["apk", "update"])

    def link_nvim(self):
        print("Link NVIM")
        self.exec([
            "ln", "-sf",
            self.system_info().home() + "/neovim/build/bin/nvim",
            "/bin/nvim"
        ])
        code, result = self.exec([
            "nvim", "--version"
        ])
        print("NVIM installed", code, result)

    def sync_config(self, overwrite: bool = True):
        sys_info = self.system_info()
        local_home = os.environ["HOME"]
        config_folder = sys_info.home() + "/.config"
        self.exec([
            "mkdir", "-p", config_folder
        ])
        self.exec([
            "mkdir", "-p", sys_info.home() + '/.local/share/nvim'
        ])
        if not overwrite and self.file_exists(config_folder + "/nvim", is_dir=True):
            return

        print("Syncing .config/nvim")
        self.exec([
            "rm", "-rf", config_folder + "/nvim"
        ])
        self.exec([
            "rm", "-rf", sys_info.home() + '/.local/share/nvim'
        ])
        self.copy(
            to_docker=True, 
            from_path=local_home + "/.config/nvim",
            to_path=config_folder + "/nvim",
        )
        self.copy(
            to_docker=True,
            from_path=local_home + '/.local/share/nvim',
            to_path=sys_info.home() + '/.local/share/nvim',
        )
        # self.exec(["rm", "-rf", config_folder + "/nvim/lazy-lock.json"])

    def install(self, packages: List[str], lean: bool = False):
        self.install_setup()
        sys_info = self.system_info()
        install_system = sys_info.install_system
        command = [
            "apt-get", "install", "-y",
        ] if install_system == "apt-get" else ["apk", "add"]
        if lean and install_system == "apt-get":
            command.append("--no-install-recommends")
        code, output = self.exec(command + packages)
        print("Installed ", packages, code)
        if code != 0:
            raise RuntimeError(f"Intall failed {packages}: {output=}")


    def ensure_deps(self):
        self.install_setup()
        self.install(["gcc", "g++", "wget", "rgrep", "git"])
        sys_info = self.system_info()

        if not sys_info.installed["node"]:
            self.install(["nodejs", "npm"], lean=True)

        if not sys_info.installed["python3"]:
            self.install(["python3"])

    def build_neovim(self, version: str = "stable", overwrite=False):
        sys_info = self.system_info()
        if not overwrite and sys_info.installed["nvim"]:
            return
        self.install([
            "curl", "unzip", "make", "gettext", "cmake",
        ])
        zip_location = "/tmp/neovim.zip"
        if not self.file_exists(zip_location, is_dir=False):
            print(f"Downloading Neovim {version=}")
            code, _ = self.exec([
                "curl", "-L", "-o",
                zip_location,
                f"https://github.com/neovim/neovim/archive/refs/tags/{version}.zip"
            ])


        if not self.file_exists(f"/tmp/neovim-{version}", is_dir=True):
            code, _ = self.exec([
                "unzip", "-oq", zip_location, "-d","/tmp/"
            ])
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
                "install",
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
        _, data = _run([
            "docker",
            "ps",
            "--format",
            "json"
        ])
        results = [DockerSummary.from_json_string(row) for row in data.splitlines()]
        if name:
            results = [e for e in results if name in e.names]
        return results



parser = argparse.ArgumentParser(
    prog="dvnim",
    description="Handle creating Neovim setup within Docker Containers",
)
parser.add_argument("container_name", default="", nargs="?")
parser.add_argument("--sync-config", action="store_true")
parser.add_argument("-b","--build", action="store_true")
parser.add_argument("-s","--store", action="store_true")

def main() -> None:
    args = parser.parse_args()
    processes = Docker.ps()
    registry = Registry()
    registry.load()
    container_name = args.container_name
    if not container_name:
        print("Pick a conatiner")
        for i, p in enumerate(processes):
            print(i, "  ", p.names)
        container_name = input("\n")

    processes = [
        pro for i, pro in enumerate(processes) 
        if container_name in pro.names or str(i) == container_name
    ]
    if not processes:
        print("Couldn't find container ", container_name)
        print([p.names for p in processes])
        return 
    docker = processes[0]
    docker.ensure_deps()
    docker.sync_config(overwrite=args.sync_config)
    info = docker.system_info()
    if not args.build and not info.installed["nvim"]:
        desc = registry.find(BuildDesc(
            arch=info.arch,
            interperter="ld_musl_aarch64" if info.ld_musl_aarch64 else "",
            image_name=docker.names,
            version="",
            luajit="",
            compile_details="",
        ))
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
    docker.docker_enter()



if __name__ == "__main__":
    main()
