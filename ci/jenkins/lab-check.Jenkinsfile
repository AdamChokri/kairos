// ci/jenkins/lab-check.Jenkinsfile - the WP1.4 check that each agent label runs a build
// (pasted into a Pipeline job "lab-agents-check"; not part of the Kairos pipeline).
pipeline {
    agent none
    options {
        timestamps()
    }
    stages {
        stage('build label') {
            agent { label 'build' }
            steps {
                sh 'hostname && id && docker version --format "Docker {{.Server.Version}}"'
            }
        }
        stage('deploy label') {
            agent { label 'deploy' }
            steps {
                // dso-jenkins runs the controller in Docker, so the docker binary exists on the VM.
                // What D-05 requires is that the deploy agent's account cannot use it (E-26):
                // not in the docker group, and refused by the Docker socket.
                sh 'hostname && id && cosign version 2>&1 | grep GitVersion && bao version && testssl.sh --version | grep -m1 -i version && ! id -nG | grep -qw docker && ! docker info >/dev/null 2>&1 && echo "no Docker access for $(id -un)"'
            }
        }
    }
}
