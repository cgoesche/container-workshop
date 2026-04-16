# OVHcloud Montreal Open Doors
## Building containers from scratch - Workshop resources

### Description

This guide will help you achieve the different learning objectives presented during the workshop and give you a practical demonstration of the foundational mechanisms allowing the creation of today's containers, and, hopefully, help you answer some confusing questions around this topic.

### Prerequisites

#### Check kernel namespace and cgroupv2 support

To successfully create a basic container-like process some kernel features have to be enabled on your running system. You can check these by running the command below and confirming the output is the same.

```Bash
# namespaces
$ grep -E '^CONFIG_(UTS|USER|PID)_NS' /boot/config-$(uname -r)
CONFIG_UTS_NS=y
CONFIG_USER_NS=y
CONFIG_PID_NS=y

# cgroupv2
$ mount -l | grep cgroup
cgroup2 on /sys/fs/cgroup type cgroup2
```

#### User namespace settings

Some distributions do not allow the creation of user namespaces by unprivileged users. The value of the output should be greater than 0.

```Bash
$ cat /proc/sys/user/max_user_namespaces
# or
$ sysctl -n user.max_user_namespaces
```

Should the value not be greater than 0, then run the following command.

```Bash
$ sudo sysctl -w user.max_user_namespaces=10000
```

#### Packages

```Bash
# Fedora/RHEL
$ sudo dnf install mkosi
# Debian/Ubuntu
$ sudo apt install mkosi
```

### Building the container

After running the commands below we will achieve the creation of a basic unprivileged container based on Debian 13 (Trixie) with internet connectivity and root level privileges inside of the container.

#### Creating the root filesystem

The configuration for `mkosi` can be found in `mkosi.conf`.

```Bash
$ mkdir mkosi.output
$ mkosi clean
$ mkosi
```

#### User/group ID mapping

We will set some environment variables for the user/group id mappings that are going to be useful in a later command.

```Bash
$ cat /etc/subuid
username:524288:65536
export START_UID_HOST="524288"
export UID_MAP_RANGE_SIZE="65536"

$ cat /etc/subgid
username:524288:65536
export START_GID_HOST="524288"
export GID_MAP_RANGE_SIZE="65536"
```

What the above means is that we can start mapping up to `65536` UIDs in the new user namespace starting from the UID `524288` on the host. The same goes for the GIDs.

#### Creating new namespaces

We are going to create four new namespaces, namely PID, UTS, mount and User and launch `bash` as first process in it.

```Bash
$ unshare --fork --kill-child --pid --uts --mount --mount-proc --user --map-users=0:1${UID}:1 --map-users=1:${START_HOST_UID}:${UID_MAP_RANGE_SIZE} --map-groups=0:${UID}$:1 --map-groups=1:${START_HOST_GID}:${GID_MAP_RANGE_SIZE} bash --norc --noprofile
```


Set the mount propagation flag for the new mount namespace recursively to private. This is important as we do not want any mount operations to be seen in the parent (host) mount namespace. It is also necessary to make `pivot_root` work as the swap of root file systems would otherwise affect the host mount namespace and cause an error.

```Bash
$ mount --make-rprivate /
```

#### Prepare the new root file system

The tool we will use to swap the root file system mount point (`pivot_root`) requires an actual mount point as argument for the `new rootfs`, thus we will turn the directory of our rootfs
into an actual mount point to then perform the swap.

We also create a directory `oldrootfs` where we will mount the old root filesystem, so we can detach it later.

```Bash
$ cd mkosi.output
$ mount --bind container-rootfs/ container-rootfs/
$ cd container-rootfs/
$ mkdir -p oldrootfs
```

#### Pivot the root file systems

Here the new mount namespace's absolute root will be the mount point we created for the new root filesystem.

```Bash
$ pivot_root . oldrootfs
cd /
```

#### Mount proc filesystem

 The proc filesystem is a pseudo-filesystem which provides an interface to kernel data structures, essentially showing process and system information.

```Bash
$ mount -t proc proc /proc
```

#### Prepare /dev

This is needed because we cannot create device nodes like the terminal multiplexer on the bare directory that is bound to the host's mount namespace. Therefore we have to create a clean slate in our mount namespace that is easily disposed after boot, thus the `tmpfs`. The `nosuid` is for defense-in-depth, as we don't want to create binaries that can escalate privileges on the host, in this case to our own user.

```Bash
$ mount -t tmpfs -o mode=755,nosuid tmpfs /dev
```

#### Create a new pseudo-terminal multiplexer instance

Having a pseudo-terminal multiplexer instance dedicated for this new mount namespace removes the risk of sharing the same as the host, to prevent unintended security concerns.

```Bash
$ mkdir -p /dev/pts
$ mount -t devpts devpts dev/pts/ -o newinstance,ptmxmode=0666,mode=620
# A lot of applications still look for the legacy location `/dev/ptmx` to create pseudo-terminals
$ ln -s /dev/pts/ptmx /dev/ptmx
```

#### Populating /dev

We borrow the already created /dev nodes in the host's root file system and create a mount point for them in our container.

```Bash
$ touch /dev/{null,random,zero}
$ mount --bind /oldrootfs/dev/null /dev/null
$ mount --bind /oldrootfs/dev/random /dev/random
$ mount --bind /oldrootfs/dev/zero /dev/zero
```


The commands below create files that resolve to each process's file descriptors 0,1 and 2, as the kernel dynamically resolves `self` to the calling process's PID.
`/dev/{stdin,sdtout,stderr}` are needed for the proper functioning of I/O of some commands like `bash`, `sed`, or `grep`.
```Bash
$ ln -s /proc/self/fd /dev/fd
$ ln -s /proc/self/fd/0 /dev/stdin
$ ln -s /proc/self/fd/1 /dev/stdout
$ ln -s /proc/self/fd/2 /dev/stderr
```

#### Detach the old host root filesystem from the file hierarchy

This will also make all mount points reachable via the old root file system invisible.
```Bash
$ umount -l /oldrootfs
$ rmdir /oldrootfs
```

#### Re-initialize the shell in the new environment

Doing this will ensure we are running the bash binary from the new root file system we created earlier, detaching the handle we had to the one we ran from the old root fs, giving us the new clean and isolated container environment we need.
```Bash
$ exec /bin/bash --norc --noprofile
```

### Setting up resource allocation limits

#### Create a cgroup

```Bash
# Run on the host
$ sudo mkdir /sys/fs/cgroup/container-group
```

Activate PID control

```Bash
$ echo "+pids" | sudo tee /sys/fs/cgroup/container-group/cgroup.subtree_control
```

Set maximum amount of additional processes
```Bash
$ echo 10 | sudo tee /sys/fs/cgroup/container-group/pids.max
```


