![main](https://github.com/marcindulak/k3s-apparmor-demo/workflows/main/badge.svg)

# Description

A demonstration of an [AppArmor](https://en.wikipedia.org/wiki/AppArmor) profile to
**allow** `cat` access to a Kubernetes secret.

This demo requires an OpenSUSE or Ubuntu, preferably in a virtual machine, due to a risk
of locking yourself out when working with AppArmor.
The recommended way of following the demo is using
[virtualbox](https://www.virtualbox.org/) and [vagrant](https://www.vagrantup.com/).

# Introduction

[AppArmor](https://en.wikipedia.org/wiki/AppArmor) is a Linux kernel security module,
created in 1998 used to restrict capabilities of executed programs.
AppArmor was first available in SUSE, later became part of Ubuntu, and in 2010 got integrated into the Linux kernel.

AppArmor allows to control programs access to network, filesystem write/read capabilities and others,
by defining text-based profiles.
It provides a [mandatory access control](https://en.wikipedia.org/wiki/Mandatory_access_control) (MAC),
meaning the policies are set globally, and the regular users of the system have no rights to override the policies.
Another popular Linux security kernel module, similar to AppArmor
however more feature [rich](https://www.redhat.com/sysadmin/apparmor-selinux-isolation),
is [SELinux](https://en.wikipedia.org/wiki/Security-Enhanced_Linux).
SELinux originated at National Security Agency (NSA) around year 2000, and is supported primarily by Red Hat.

# Demo

## Initial setup

1. Clone this repository
  ```sh
  git clone https://github.com/marcindulak/k3s-apparmor-demo
  cd k3s-apparmor-demo
  ```
  Clone the demo-magic demo execution helper script
  ```sh
  git clone https://github.com/paxtonhare/demo-magic
  ```

2. If working with vagrant, bring up the virtual machine, and ssh into it, choose opensuse or ubuntu
  ```sh
  vagrant up
  vagrant ssh ubuntu
  ```

3. Bring up [k3s](https://k3s.io/) with the
[AppArmor feature gate enabled](https://kubernetes.io/docs/tutorials/clusters/apparmor/#disabling-apparmor).
Beware that the k3s installation will attempt to gain root/sudo.
  ```sh
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.21.2+k3s1 sh -s - --kube-apiserver-arg=feature-gates=AppArmor=true
  ```
  Change the owner of the kubeconfig files created by k3s
  ```sh
  sudo chown vagrant.vagrant /etc/rancher/k3s/k3s.yaml
  ```


## File read deny profile on the host

The goal of the demo is to **allow** `cat` and only `cat` to access the secret `/etc/secret/favorite` mounted in a pod.
Inside of the secret is one of cat's favorite things. Other programs should not have access to this secret.

Before reaching the goal of the demo, let's first, using a modified example from the official
[Kubernetes AppArmor](https://kubernetes.io/docs/tutorials/clusters/apparmor)
documentation, create an AppArmor profile to **deny** `cat` read access to the secret.

4. Create the AppArmor profile called `secret-access` under `/etc/apparmor.d/`
  ```sh
  sudo dd status=none of=/etc/apparmor.d/secret-access << 'EOF'
# vim:syntax=apparmor

#include <tunables/global>

profile secret-access /{,usr/}bin/cat {
  #include <abstractions/base>

  file,  # Allow all files access
  deny /etc/secret/** r,  # Deny read to /etc/secret and its subdirectories and files
}
EOF
  ```
  Please note that storing a profile under `/etc/apparmor.d` does not automatically enable it.
  A new profile needs to be explicitly loaded.

5. Before loading the `secret-access` profile, confirm that `cat` has access to
the `/etc/secret/favorite` file on the host
  ```sh
  sudo mkdir -p /etc/secret
  sudo sh -c 'echo 1 > /etc/secret/favorite'
  cat /etc/secret/favorite
  1  
  ```
  As expected, since the `secret-access` profile is not active yet,
  `cat` can read the value of `1` stored in the `/etc/secret/favorite` file on the host.

6. Load the profile and confirm it's loaded
  ```sh
  sudo apparmor_parser -r /etc/apparmor.d/secret-access
  sudo aa-status | grep secret-access
  ```

7. Verify that `cat` cannot read `/etc/secret/favorite` anymore, however other programs still can.
The exclamation mark followed by a space at the line beginning negates the exit status of the command,
so the expected failure of the command return the successful `0` status
  ```sh
  ! cat /etc/secret/favorite 
  cat: /etc/secret/favorite: Permission denied
  echo $? | grep 0
  0  
  ```
  ```sh
  tail /etc/secret/favorite
  1
  ```

We are ready for the next section.

## File read deny profile in a pod

After having tested the profile on the host, let's load the same profile onto a Kubernetes container.

8. First, create the Kubernetes secret to be mounted by the pod
  ```sh
cat << 'EOF' > secret-thing.yaml
apiVersion: v1
data:
  favorite: Y2F0bmlw
kind: Secret
metadata:
  creationTimestamp: null
  name: secret-thing
EOF
```
  Create the secret
  ```sh
  kubectl create -f secret-thing.yaml
  ```

The association between the container and AppArmor profile is made using the
following [annotation](https://kubernetes.io/docs/tutorials/clusters/apparmor).

```
container.apparmor.security.beta.kubernetes.io/<container_name>: <profile_ref>
```

9. Create a pod using the following `pod-secret-access.yaml` manifest.
Note the AppArmor annotation that refers to container `container` and
uses the AppArmor policy `secret-access` loaded on the localhost.
  ```sh
cat << 'EOF' > pod-secret-access.yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-secret-access
  annotations:
    container.apparmor.security.beta.kubernetes.io/container: localhost/secret-access
spec:
  containers:
    - name: container
      image: busybox
      command: ["sleep", "infinity"]
      volumeMounts:
      - name: volume-secret
        mountPath: /etc/secret
  volumes:
  - name: volume-secret
    secret:
      secretName: secret-thing
EOF
  ```
  Create the pod
  ```sh
  kubectl create -f pod-secret-access.yaml
  kubectl wait --for=condition=Ready pod/pod-secret-access
  ```

10. Verify the behavior of the profile in a container. Note that contrary to the
behavior on the host, inside of the container the `secret-access` profile blocks
reads by all programs, not just `cat`, but also `tail` for example
  ```sh
  ! kubectl exec -it pod-secret-access -- cat /etc/secret/favorite
  cat: /etc/secret/favorite: Permission denied
  command terminated with exit code 1
  ```
  ```sh
  ! kubectl exec -it pod-secret-access -- tail /etc/secret/favorite
  tail: cannot open '/etc/secret/favorite' for reading: Permission denied
  command terminated with exit code 1
  ```

Note that this AppArmor profile on the host behaves differently when assigned to a container.
On a host, every program may have its own profile, however a container in a Kubernetes pod can only have one profile.
This makes the AppArmor profile creation process for containers difficult.

11. Let's remove the unsatisfactory profile (this removes also dynamically loaded profiles)
  ```sh
  sudo rm /etc/apparmor.d/secret-access
  sudo aa-remove-unknown
  ```

12. Verify that `cat` can read the secret again on the host
  ```sh
  cat /etc/secret/favorite
  1
  ```

13. Notice however, that while the pod is still "Running", the `exec` into the pod no longer works
  ```sh
  kubectl get pod
  NAME                READY   STATUS    RESTARTS   AGE
  pod-secret-access   1/1     Running   0          14m
  ! kubectl exec -it pod-secret-access -- cat /etc/secret/favorite
error: Internal error occurred: error executing command in container: failed to exec in container: failed to start exec "a50d679775cbdc42c72ca2fc57937b24bbab7cf6a3b61e2183743137798bf611": OCI runtime exec failed: exec failed: container_linux.go:380: starting container process caused: apparmor failed to apply profile: write /proc/self/attr/apparmor/exec: no such file or directory: unknown
  ```

14. Recreate the pod to notice that an AppArmor profile present in pod annotations,
but not loaded on the host, results in a "Blocked" pod status
  ```sh
  kubectl delete -f pod-secret-access.yaml --force --grace-period=0
  kubectl create -f pod-secret-access.yaml
  kubectl get pod
  NAME                READY   STATUS    RESTARTS   AGE
  pod-secret-access   0/1     Blocked   0          2m54s
  kubectl describe pod pod-secret-access | grep -A 2 Pending
  Status:       Pending
  Reason:       AppArmor
  Message:      Cannot enforce AppArmor: profile "secret-access" is not loaded
  ```

15. Disable the AppArmor `feature-gate` in the Kubernetes `kube-apiserver` configuration
  ```sh
  sudo sed -i 's/feature-gates=AppArmor=true/feature-gates=AppArmor=false/' /etc/systemd/system/k3s.service
  sudo systemctl daemon-reload
  sudo systemctl restart k3s
  ```
  Notice that the pod is still "Blocked"
  ```sh
  kubectl get pod
  NAME                READY   STATUS    RESTARTS   AGE
  pod-secret-access   0/1     Blocked   0          80s
  ```
  Then confirm that with AppArmor disabled, a freshly started, annotated pod is "Running",
  and `cat` inside of the container has access to the secret.
  Let's not reveal the secret as for now.
  ```sh
  kubectl delete -f pod-secret-access.yaml --force --grace-period=0
  kubectl create -f pod-secret-access.yaml
  kubectl wait --for=condition=Ready pod/pod-secret-access  
  kubectl exec -it pod-secret-access -- cat /etc/secret/favorite > /dev/null
  kubectl delete -f pod-secret-access.yaml --force --grace-period=0  
  ```
  Then enable the AppAppmor in `kube-apiserver` again
  ```sh
  sudo sed -i 's/feature-gates=AppArmor=false/feature-gates=AppArmor=true/' /etc/systemd/system/k3s.service
  sudo systemctl daemon-reload
  sudo systemctl restart k3s
  ```

We are ready for the next section.

## Allow `cat` to read the secret

This is the awaited part of the demo, where only `cat` gets access to the secret.

15. Load the final `secret-access` profile. Look into the `secret-access` file and analyse it
with help of the example from the
[Breaking an AppArmor Profile into Its Parts](https://doc.opensuse.org/documentation/leap/security/single-html/book-security/index.html#sec-apparmor-profiles-parts)
document. Additional AppArmor documentation resources are given further down.
```sh
sudo dd status=none of=/etc/apparmor.d/secret-access << 'EOF'  
# vim:syntax=apparmor

#include <tunables/global>

profile secret-access {
  #include <abstractions/base>

  # Executables

  /{,usr/}bin/cat cx -> allow,

  /{,usr/}bin/** cx -> deny,

  profile allow {
    #include <abstractions/base>

    /{,usr/}bin/** mrPix,  # Try to use an existing program profile

    /** rw,  # Allow read/write to / and its subdirectories and files
    /etc/secret/** r,  # Allow read of /etc/secret and its subdirectories and files
  }

  profile deny {
    #include <abstractions/base>

    /{,usr/}bin/** mrPix,  # Try to use an existing program profile

    /** rw,  # Allow read/write to / and its subdirectories and files
    deny /etc/secret/** rw,  # Deny read/write to /etc/secret and its subdirectories and files
  }
}
EOF
```
  Load the profile on the host
  ```sh
  sudo apparmor_parser -r /etc/apparmor.d/secret-access
  sudo aa-status | grep secret-access  
  ```
  Notice that this profile does not block read access on the host
  ```sh
  tail /etc/secret/favorite
  ```

16. Create the pod and verify that only `cat` has access to the secret.
  ```sh
  kubectl create -f pod-secret-access.yaml
  kubectl wait --for=condition=Ready pod/pod-secret-access
  ```
  Verify both using the `command` and `shell` kubectl access.
  ```sh
  ! kubectl exec -it pod-secret-access -- tail /etc/secret/favorite
  ! kubectl exec -it pod-secret-access -- sh -c 'tail /etc/secret/favorite'
  ! kubectl exec -it pod-secret-access -- cat /etc/secret/favorite
  ```
  Read the secret
  ```sh
  kubectl exec -it pod-secret-access -- sh -c 'cat /etc/secret/favorite'
  ```


# Conclusions

The created AppArmor profile seems to achieve the goal of the demo. However, it should be noted that it's
more of a hack than a proper AppArmor profile, which probably would be more complex.
It can be verified that the above `secret-access` profile does not grant all programs their default access,
moreover the pod is missing other capabilities like network access.

Improvements to this demo are welcomed!


# AppArmor documentation


https://doc.opensuse.org/documentation/leap/security/single-html/book-security/index.html#part-apparmor
https://www.apertis.org/guides/apparmor/
https://gitlab.com/apparmor/apparmor/-/wikis/QuickProfileLanguage

# License

Apache-2.0


# Todo

