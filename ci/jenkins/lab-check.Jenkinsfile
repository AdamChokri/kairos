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
                sh 'hostname && id && cosign version 2>&1 | grep GitVersion && bao version && testssl.sh --version | grep -m1 -i version && ! command -v docker'
            }
        }
    }
}
