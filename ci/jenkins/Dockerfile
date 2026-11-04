# ci/jenkins/Dockerfile - the Jenkins controller image (plan WP1.4, D-01).
# Base image pinned by digest (ci/tools/pin-images.sh); plugins pinned in plugins.txt
# (ci/jenkins/pin-plugins.sh). Built on dso-jenkins by the Ansible role jenkins-controller,
# which adds the lab CA certificate (infra/pki/kairos-lab-ca.crt) to the build context.
FROM jenkins/jenkins:lts-jdk21@sha256:74401de6a6f92e1afe1b02d1c8e3d0c33f263bfb5275dd8813f9150355f2367b

# The lab CA, trusted by the JVM (the Vault plugin's TLS to OpenBao) and by the system (git, curl).
# USER by number: 0 is root, 1000 the image's jenkins account.
USER 0
COPY kairos-lab-ca.crt /usr/local/share/ca-certificates/kairos-lab-ca.crt
RUN update-ca-certificates \
 && keytool -importcert -noprompt -cacerts -storepass changeit \
      -alias kairos-lab-ca -file /usr/local/share/ca-certificates/kairos-lab-ca.crt
USER 1000:1000

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Groovy scripts run at every start; ".override" makes Jenkins refresh them from the image.
COPY --chown=jenkins:jenkins init.groovy.d/ /usr/share/jenkins/ref/init.groovy.d/
