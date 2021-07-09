#!/usr/bin/env bash

set -e

NO_WAIT_USE="${NO_WAIT:-false}"

. demo-magic/demo-magic.sh

TYPE_SPEED=180

NO_WAIT=${NO_WAIT_USE}

BOLD="\033[1m"

DEMO_PROMPT=""
DEMO_CMD_COLOR=${BOLD}
DEMO_COMMENT_COLOR=${BLUE}

preamble() {
    p "################################################################################
#                              Cat vs AppArmor                                 #
################################################################################"
    echo
    p "# A demonstration of an AppArmor profile to **allow** \`cat\` access to a Kubernetes secret."
    echo
    p "# Warning! When experimenting with AppArmor consider using a virtual machine due to a risk of **locking yourself out**!"
    echo
    echo -e "In this demo comments are ${BLUE}blue${COLOR_RESET}, and commands are ${BOLD}bold${COLOR_RESET}"
    echo
}

setup() {
    p "################################################################################
#                              Initial setup                                   #
################################################################################"
    echo
    p "# Bring up k3s with the AppArmor feature gate enabled"
    pei "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.21.2+k3s1 sh -s - --kube-apiserver-arg=feature-gates=AppArmor=true"
    echo
    p "# Change the owner of the kubeconfig file created by k3s"
    pei "sudo chown ${USER} /etc/rancher/k3s/k3s.yaml"
    pei "sudo ls -al /etc/rancher/k3s"
    echo    
    p "# Set the KUBECONFIG environment variable"
    pei "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
    echo
    p "# Make sure the k8s node has STATUS Ready"
    pei "kubectl wait --for=condition=Ready node/${HOSTNAME}"
    pei "kubectl get node"
    echo
    p "# We are ready for the next section."
}

cleanup() {
    sudo apparmor_parser -Rq /etc/apparmor.d/secret-* 2&>1 > /dev/null || true
    sudo rm -f /etc/apparmor.d/secret-*
    sudo aa-remove-unknown 2&>1 > /dev/null || true
    kubectl delete pod pod-secret-access --force --grace-period=0 2&>1 > /dev/null || true
    kubectl delete secret secret-thing 2&>1 > /dev/null || true
}

deny_on_host() {
    p "################################################################################
#                    File read deny profile on the host                        #
################################################################################"
    echo
    p "# Before reaching the goal of the demo, let's first, using a modified example from the official
Kubernetes AppArmor documentation, create an AppArmor profile to **deny** \`cat\` read access to the secret."
    echo
    p "# Create the AppArmor profile called \`secret-access\` under \`/etc/apparmor.d/\`"
    pei "sudo dd status=none of=/etc/apparmor.d/secret-access << 'EOF'
# vim:syntax=apparmor

#include <tunables/global>

profile secret-access /{,usr/}bin/cat {
  #include <abstractions/base>

  file,  # Allow all files access
  deny /etc/secret/** r,  # Deny read to /etc/secret and its subdirectories and files
}
EOF"
    echo
    p "# Before loading the \`secret-access\` profile, confirm that \`cat\` has access to
the \`/etc/secret/favorite\` file on the host"
    pei "sudo mkdir -p /etc/secret
sudo sh -c 'echo 1 > /etc/secret/favorite'
cat /etc/secret/favorite"
    echo
    p "# As expected, since the \`secret-access\` profile is not active yet,
\`cat\` can read the value of \`1\` stored in the \`/etc/secret/favorite\` file on the host"
    echo
    p "# Load the profile and confirm it's loaded"
    pei "sudo apparmor_parser -r /etc/apparmor.d/secret-access
sudo aa-status | grep secret-access"
    echo
    p "# Verify that \`cat\` cannot read \`/etc/secret/favorite\` anymore, however other programs still can"
    pei "! cat /etc/secret/favorite"
    pei "tail /etc/secret/favorite"
    echo
    p "# We are ready for the next section."
    }

deny_in_pod() {
    p "################################################################################
#                      File read deny profile in a pod                         #
################################################################################"
    echo
    p "# After having tested the profile on the host, let's load the same profile onto a Kubernetes container."
    echo
    p "# First, create the Kubernetes secret to be mounted by the pod"
    pei "cat << 'EOF' > secret-thing.yaml
apiVersion: v1
data:
  favorite: Y2F0bmlwIPCfjL8K
kind: Secret
metadata:
  creationTimestamp: null
  name: secret-thing
EOF"
    p "# Create the secret"
    pei "kubectl create -f secret-thing.yaml"
    echo
    p "# Create a pod using the following \`pod-secret-access.yaml\` manifest. Note the apparmor annotation"
    pei "cat << 'EOF' > pod-secret-access.yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-secret-access
  annotations:
    container.apparmor.security.beta.kubernetes.io/container: localhost/secret-access
spec:
  containers:
    - name: container
      image: ubuntu
      command: ["sleep", "infinity"]
      volumeMounts:
      - name: volume-secret
        mountPath: /etc/secret
  volumes:
  - name: volume-secret
    secret:
      secretName: secret-thing
EOF"
    p "# Create the pod"
    pei "kubectl create -f pod-secret-access.yaml"
    pei "kubectl wait --for=condition=Ready pod/pod-secret-access"
    pei "kubectl get pod"
    echo
    p "# Verify the behavior of the profile in a container"
    pei "! kubectl exec -it pod-secret-access -- cat /etc/secret/favorite"
    pei "! kubectl exec -it pod-secret-access -- tail /etc/secret/favorite"
    echo
    p "# Note that this AppArmor profile on the host behaves differently when assigned to a container.
AppArmor limits the capabilities on the process level. Let's get the information
about the process confinement inside of the container"
    pei "kubectl exec -it pod-secret-access -- bash -c 'sleep 0 & tail & cat & ps auxZ'"
    echo
    p "# Let's remove the unsatisfactory profile"
    pei "sudo apparmor_parser -R /etc/apparmor.d/secret-*"
    echo
    p "# Verify that \`cat\` can read the secret again on the host"
    pei "cat /etc/secret/favorite"
    echo
    p "# Let's also delete the pod"
    pei "kubectl delete -f pod-secret-access.yaml --force --grace-period=0"
    echo
    p "# We are ready for the next section."
}

allow_cat() {
    p "################################################################################
#                       Allow \`cat\` to read the secret                         #
################################################################################"
    echo
    p "# This is the awaited part of the demo, where only \`cat\` gets access to the secret."
    echo
    p "# Load the final \`secret-access\` profile"
    pei "sudo dd status=none of=/etc/apparmor.d/secret-access << 'EOF'
# vim:syntax=apparmor

#include <tunables/global>

profile secret-access {
  #include <abstractions/base>

  /{,usr/}bin/cat Cx -> allow,  # Transition to child (local-profile)

  /{,usr/}bin/** Cx -> deny,  # Transition to child (local-profile)

  profile allow {
    #include <abstractions/base>

    /{,usr/}bin/** ix,  # Execute the program inheriting the current profile

    file,  # Allow all files access
    /etc/secret/** r,  # Allow read of /etc/secret and its subdirectories and files
  }

  profile deny {
    #include <abstractions/base>

    /{,usr/}bin/** ix,  # Execute the program inheriting the current profile

    file,  # Allow all files access
    deny /etc/secret/** rw,  # Deny read/write to /etc/secret and its subdirectories and files
  }
}
EOF"
    echo
    p "# Load the profile on the host"
    pei "sudo apparmor_parser -r /etc/apparmor.d/secret-access
sudo aa-status | grep secret-access"
    echo
    p "# Notice that this profile does not block read access on the host"
    pei "tail /etc/secret/favorite"
    echo
    p "# Create the pod and verify that only \`cat\` has access to the secret"
    pei "kubectl create -f pod-secret-access.yaml"
    pei "kubectl wait --for=condition=Ready pod/pod-secret-access"
    pei "kubectl get pod"
    echo
    p "# Verify both using the \`command\` and \`shell\` kubectl access. Note the difference!"
    pei "! kubectl exec -it pod-secret-access -- tail /etc/secret/favorite"
    pei "! kubectl exec -it pod-secret-access -- sh -c 'tail /etc/secret/favorite'"
    pei "! kubectl exec -it pod-secret-access -- cat /etc/secret/favorite"
    echo
    p "# Let's get the information about the process confinement inside of the container"
    pei "kubectl exec -it pod-secret-access -- bash -c 'sleep 0 & tail & cat & ps auxZ'"
    echo
    p "# Read the secret"
    pei "kubectl exec -it pod-secret-access -- sh -c 'cat /etc/secret/favorite'"
    # https://emojipedia.org/herb/
    echo
    p "# We are ready for the conclusions."
}

finale() {
    echo
    p "# The created AppArmor profile seems to achieve the goal of the demo.
However, it should be noted that a complete profile would be more complex.
It can be also verified that the above \`secret-access\` profile does not provide all programs
their default access, moreover the pod is missing other capabilities like network access."
    echo
    p "################################################################################
#                               End of Demo                                    #
################################################################################"
}

clear
preamble

setup
clear

cleanup

deny_on_host
clear

deny_in_pod
clear

allow_cat

finale
