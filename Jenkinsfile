// Jenkinsfile - Kairos DevSecOps pipeline, state of P4 (plan Appendix C).
// Lanes: pull requests and other branches run the CI controls with no secret at all; main adds SonarQube.
// Every control is a script of ci/scripts/ that applies its own threshold from security/policy/gates.env and ends
// with the exit-code protocol of runControl below.
// The seven stages after ci are placeholders: each prints one line and does nothing (D-46).
// Secrets come from OpenBao through withVault (credential bao-build, an AppRole bound to dso-jenkins) and are
// used only inside single-quoted sh steps, so Groovy never interpolates them. Pull-request builds bind none.

// Binding variables (no `def`): runControl and the post section both see them.
failedControls = []     // controls that blocked or failed in this build: named in the Slack message
reportedControls = []   // controls that would block, in report mode

// Runs one control script. Exit 0 = pass, 1 = blocked, 2 = would block (control in report mode: the stage turns
// yellow, the build stays green), any other code = the tool or the script failed, which always fails the build.
def runControl(String name) {
  int rc = sh(script: "ci/scripts/${name}.sh", returnStatus: true)
  if (rc == 2) {
    reportedControls << name
    catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
      error("${name}: findings above the threshold (report mode), see reports/")
    }
  } else if (rc != 0) {
    failedControls << name
    catchError(buildResult: 'FAILURE', stageResult: 'FAILURE') {
      error("${name}: blocked by its gate or tool error (exit ${rc}), see reports/")
    }
  }
}

// One trend chart per tool: every scanner writes SARIF, Warnings Next Generation reads it.
def recordSarif(String toolId, String toolName, String pattern) {
  recordIssues(enabledForFailure: true, skipBlames: true, skipPublishingChecks: true, ignoreQualityGate: true,
               tool: sarif(id: toolId, name: toolName, pattern: pattern))
}

def notifySlack(String color, String text) {
  node('build') {
    slackSend(channel: '#kairos-ci', color: color,
              message: "${env.JOB_NAME} #${env.BUILD_NUMBER} ${text} - ${env.BUILD_URL}artifact/reports/")
  }
}

pipeline {
  agent none
  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '30', artifactNumToKeepStr: '15'))
    timeout(time: 4, unit: 'HOURS')               // overall cap
  }
  stages {
    stage('ci') {
      agent { label 'build' }
      options { timeout(time: 45, unit: 'MINUTES') }
      stages {
        stage('preflight')    { steps { script { runControl('preflight') } } }
        stage('secrets_scan') { steps { script { runControl('secrets_scan') } } }
        stage('build_test')   { steps { script { runControl('build_test') } } }
        stage('sast') {
          when { expression { !failedControls.contains('build_test') } }   // it needs the environments build_test made
          steps {
            script {
              if (env.BRANCH_NAME == 'main') {
                // SonarQube Community Build analyses main only (D-09); only main gets its token.
                withVault(configuration: [vaultCredentialId: 'bao-build'],
                          vaultSecrets: [[path: 'kv/ci/sonarqube',
                                          secretValues: [[envVar: 'SONAR_TOKEN', vaultKey: 'token']]]]) {
                  runControl('sast')              // Semgrep, Bandit, ESLint, then SonarQube with the quality-gate wait
                }
              } else {
                runControl('sast')                // Semgrep, Bandit, ESLint: no secret on this lane
              }
            }
          }
        }
        stage('scan_dependencies') { steps { script { runControl('sca') } } }
        stage('iac_scan')          { steps { script { runControl('iac') } } }
        stage('build_images')      { steps { script { runControl('build_images') } } }
        stage('docker_scan') {
          when { expression { !failedControls.contains('build_images') } }
          steps { script { runControl('image_scan') } }
        }
      }
      post {
        always {
          // Reports: one entry per scanner, then tests, the HTML of Trivy, and every file of reports/ as an artifact.
          script {
            recordSarif('semgrep', 'Semgrep', 'reports/semgrep.sarif')
            recordSarif('bandit', 'Bandit', 'reports/bandit.sarif')
            recordSarif('eslint', 'ESLint', 'reports/eslint.sarif')
            recordSarif('gitleaks', 'Gitleaks', 'reports/gitleaks-*.sarif')
            recordSarif('trivy-fs', 'Trivy dependencies', 'reports/trivy-fs-*.sarif')
            recordSarif('trivy-config', 'Trivy Dockerfiles', 'reports/trivy-config-*.sarif')
            recordSarif('trivy-image', 'Trivy images', 'reports/trivy-image-*.sarif')
            recordSarif('hadolint', 'Hadolint', 'reports/hadolint-*.sarif')
          }
          junit testResults: 'reports/junit-*.xml', allowEmptyResults: true
          publishHTML(target: [allowMissing: true, alwaysLinkToLastBuild: true, keepAll: true, reportDir: 'reports',
                               reportFiles: 'trivy-image-api.html,trivy-image-web.html', reportName: 'Trivy images'])
          archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true
          sh 'ci/scripts/build_images.sh --cleanup'   // removes this build\'s images and image files from the agent
          cleanWs()                                   // the workspace is wiped after every build (plan section 8.3)
        }
      }
    }
    // The seven stages below are placeholders (D-46): each prints one line and does nothing. The pipeline builds and
    // scans the images and stops there; nothing is published, signed, deployed or scanned dynamically (T-02).
    stage('sbom') {
      when { branch 'main' }
      steps { echo 'placeholder: no SBOM is made; the pipeline stops after the image scan (D-46)' }
    }
    stage('publish') {
      when { branch 'main' }
      steps { echo 'placeholder: nothing is published; the pipeline stops after the image scan (D-46)' }
    }
    stage('sign') {
      when { branch 'main' }
      steps { echo 'placeholder: nothing is signed; the pipeline stops after the image scan (D-46)' }
    }
    stage('deploy_staging') {
      when { branch 'main' }
      steps { echo 'placeholder: nothing is deployed to staging (D-46)' }
    }
    stage('dast') {
      when { branch 'main' }
      steps { echo 'placeholder: no dynamic scan is run (D-46)' }
    }
    stage('approve_production') {
      when { branch 'main' }
      steps { echo 'placeholder: there is no production approval to ask for (D-46)' }
    }
    stage('deploy_production') {
      when { branch 'main' }
      steps { echo 'placeholder: nothing is deployed to production (D-46)' }
    }
  }
  post {
    failure {
      script {
        String names = failedControls ? failedControls.join(', ') : 'a stage outside the controls'
        notifySlack('danger', "failed (${names})")
      }
    }
    fixed { script { notifySlack('good', 'is back to normal') } }
  }
}
