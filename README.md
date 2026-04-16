# OVHcloud Montreal Open Doors
## Building containers from scratch - Workshop resources

### Description

This guide will help you achieve the different learning objectives presented during the workshop and give you a practical demonstration of the foundational mechanisms allowing the creation of today's containers, which, hopefully, helps your understanding and 

### Prerequisites

#### Check kernel support

To successfully create a basic container-like process some kernel features have to be enabled on your running system. You can check these by running the command below and confirming the output is the same.

```Bash
$ grep -E '^CONFIG_(UTS|USER|PID)_NS' /boot/config-$(uname -r)
CONFIG_UTS_NS=y
CONFIG_USER_NS=y
CONFIG_PID_NS=y
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
sudo sysctl -w user.max_user_namespaces=10000
```

#### Packages

```Bash
# Fedora/RHEL
sudo dnf install mkosi
# Debian/Ubuntu
sudo apt install mkosi
# Suse
sudo zypper install mkosi
```


### Create the root filesystem

```Bash
mkosi clean
mkosi
```

### User/group ID mapping

```Bash
$ cat /etc/subuid
$ cat /etc/subgid
```

#### Create a process and its new namespaces

```Bash
unshare --fork --kill-child --pid --uts --time --mount --mount-proc --user --map-users=0:1000:1 --map-users=1:524288:65536 --map-groups=0:1000:1 --map-groups=1:524288:65536 bash --norc --noprofile
```


Set the mount propagation flag for the new mount namespace recursively to private. This is important as we do not want any mount operations to be seen in the parent (host) mount namespace.

```Bash
mount --make-rprivate /
```


#### Prepare the new root

The reaso

```Bash
mount --bind /tmp/my-rootfs /tmp/my-rootfs
cd /tmp/my-rootfs
mkdir -p oldrootfs
```

#### Pivot the root file systems

```Bash
pivot_root . oldrootfs
cd /
```

#### Mount Proc filesystems

```Bash
mount -t proc proc /proc
mount -t sysfs sys /sys
```

#### Prepare /dev

```Bash
mount -t tmpfs -o mode=755,nosuid tmpfs /dev
mkdir -p /dev/pts
```

#### Create a new pseudo-terminal multiplexer instance dedicated for this namespace

```Bash
mount -t devpts devpts dev/pts/ -o newinstance,ptmxmode=0666,mode=620
# Most applications look for /dev/ptmx to create pseudo-terminals
ln -s /dev/pts/ptmx /dev/ptmx
```

#### Populating /dev

```Bash
touch /dev/zero
mount --bind /oldrootfs/dev/zero /dev/zero
```

```Bash
touch /dev/null
mount --bind /oldrootfs/dev/null /dev/null
```

```Bash
touch /dev/random
mount --bind /oldrootfs/dev/random /dev/random
```


This will work for all processes in that namespace as /proc/self
will resolve dynamically to the calling process
```Bash
ln -s /proc/self/fd /dev/fd
ln -s /proc/self/fd/0 /dev/stdin
ln -s /proc/self/fd/1 /dev/stdout
ln -s /proc/self/fd/2 /dev/stderr
```

#### Detach the old host root filesystem from the file hierarchy

```Bash
umount -l /oldrootfs
rmdir /oldrootfs
```

#### Re-initialize the shell in the new environment

```Bash
exec /bin/bash --norc --noprofile
```
