def last_node_name = ''
def nodeip = ''
pipeline {
  agent any
  stages {

    stage('Get Last Node of Cluster') {
      steps {
          script {
            try {
                last_node_name = sh script:"""#!/bin/bash
                  source ./script/aerospike_delete_node.sh
                  get_last_node_metadata
                  """, returnStdout: true
                println "Agent info within script: ${last_node_name}"
              }
            catch (err) {
                currentBuild.result = 'FAILURE'
                emailExtraMsg = "Build Failure:"+ err.getMessage()
                throw err
              }
          }
        }
      }

    stage('Extract Last Node IP') {
      steps {
        script {
            try {
            nodeip = sh script:"""#!/bin/bash
                source ./script/aerospike_delete_node.sh
                extract_ip_of_last_node \$(echo "${last_node_name}")
                """, returnStdout: true
              println "Agent info within script: ${nodeip}"
              }
            catch (err) {
                currentBuild.result = 'FAILURE'
                emailExtraMsg = "Build Failure:"+ err.getMessage()
                throw err
              }
          }
        }
      }

    stage('Check Migration on Aerospike Cluster') { 
      steps {
        script {
            try { sh """#!/bin/bash
              source ./script/aerospike_delete_node.sh
              check_migration_before_delete_node_process \$(echo "${nodeip}")
              """ 
              }
            catch (err) {
                currentBuild.result = 'FAILURE'
                emailExtraMsg = "Build Failure:"+ err.getMessage()
                throw err
              }
          }     
        }  
      }

    stage('Quiece Last Node') {
      steps {
        script {
            try { sh """#!/bin/bash
              source ./script/aerospike_delete_node.sh
              quiesce_last_node \$(echo "${nodeip}")
              """
              }
            catch (err) {
                currentBuild.result = 'FAILURE'
                emailExtraMsg = "Build Failure:"+ err.getMessage()
                throw err
              }
          }
        }
      }
    stage('Display Quieced Nodes') {
      steps {
        script {
              sh """#!/bin/bash
              source ./script/aerospike_delete_node.sh
              nodes_which_got_quiesced \$(echo "${nodeip}")
              """
          }
        }
      }    
    stage('Undo quiece unwanted nodes') {
      steps {
        script {
              sh """#!/bin/bash
              source ./script/aerospike_delete_node.sh
              undo_quiesce_on_unwanted_quiesced_nodes \$(echo "${nodeip}")
              """
          }
        }
      }    
    stage('Recluster  Aerospike ') { 
      steps {
        input('Do you want to proceed?')
        script {
            sh """#!/bin/bash
              source ./script/aerospike_delete_node.sh
              output=\$(run_recluster_node \$(echo "${nodeip}"))
              echo \$output
              """
          }     
        }  
      }
    stage('Check Migrtion on Cluster after Re-clustering') { 
      steps {
          script {
              sh """#!/bin/bash
                source ./script/aerospike_delete_node.sh
                check_migration \$(echo "${nodeip}")
                """
            }     
          }  
        }
    stage('Stop the Container && Deleting node') {
      steps {
        script {
              sh """#!/bin/bash
              source ./script/aerospike_delete_node.sh
              stop_container_and_delete_node \$(echo "${nodeip}") \$(echo "${last_node_name}")
              """
          }
        }
      }
    stage('Remove DNS Record && Enrty From Inventory File') {
      steps {
        script {
              sh """#!/bin/bash
              source ./script/aerospike_delete_node.sh
              delete_dns_record_update_inventory_file \$(echo "${nodeip}") \$(echo "${last_node_name}")
              """
          }
        }
      }
    stage ('Release Branch') {
      steps {
          withCredentials([sshUserPrivateKey(credentialsId: 'jenkins-user', keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER')]){
            withEnv(["GIT_SSH_COMMAND=ssh -o StrictHostKeyChecking=no -o User=${SSH_USER} -i ${SSH_KEY}"]) {
              sh """
                branch="\$(echo ${GIT_BRANCH} | sed -e 's|origin/||g')"
                
                mkdir aerospike_clone
                cd aerospike_clone
      
                git clone -b "\${branch}" ${GIT_URL}
                cd DevOps
                
                git config --local user.email "jenkins@zypmedia.com"
                git config --local user.name "${SSH_USER}"
                
                mv ../../ansible/inventories/${inventory_env}/hosts.yaml ansible/inventories/${inventory_env}/hosts.yaml
                
                git add ansible/inventories/${inventory_env}/hosts.yaml
                git commit -m "Deleted Node with jenkins build # ${currentBuild.number} aerospike node DNS ${last_node_name}"
                git push --set-upstream origin "\${branch}"
              """
          }
        }
      }
    }
  }
  post {
    success {  
      script {
          slackSend color: "good", channel: "zypmedia-spotinst-deployment", message: "Jenkins Aerospike Delete Node Pipeline Ran Successfully \n JOB NAME:- ${env.JOB_NAME}\n BUILD NUMBER # ${env.BUILD_NUMBER}\n BUILD-URL:-${env.BUILD_URL}"
        } 
    }
    failure {  
      script {
          slackSend color: "danger", channel: "zypmedia-spotinst-deployment", message: "Jenkins Aerospike Delete Node Pipeline Failed \n JOB NAME:- ${env.JOB_NAME}\n BUILD NUMBER # ${env.BUILD_NUMBER}\n BUILD-URL:-${env.BUILD_URL}"
        } 
    }      
    always {
        sh """
        echo "Removing all the unnecessary files and directories"
        rm -rf aerospike_clone || true
        rm -rf userdata.txt || true
        """
    }
  } 
}
