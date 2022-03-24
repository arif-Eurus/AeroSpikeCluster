def node_dns = ''
def flag_node_exists=false
pipeline {
  agent any 
  stages {
      stage('Check Node Exists') {
        when {  expression { params.custom_node_check && (params.custom_node_name!=null && !params.custom_node_name.isEmpty()) } }
        steps {
          script {
            try {
              def statusCode = sh script:"""#!/bin/bash
                source ./script/aerospike_add_node.sh
                check_node_exists \$(echo "${params.custom_custom_node_name}")
                """, returnStdout: true
                flag_node_exists= statusCode != 0
                println "Agent Not Found"
              }
            catch (err) {
                currentBuild.result = 'FAILURE'
                emailExtraMsg = "Build Failure:"+ err.getMessage()
                throw err
            }
          }
        }
    }
     stage('Get Custom Node Number/Add to Host file') {
      when {  expression { (params.custom_node_name!=null && !params.custom_node_name.isEmpty())&& params.custom_node_check && flag_node_exists } }
      steps {
        script {
          try {
            node_dns = sh script:"""#!/bin/bash
              source ./script/aerospike_add_node.sh
              add_new_node_in_ansible_inventory  \$(echo "${params.custom_node_name}")
              """, returnStdout: true
              println "Agent info within script: ${node_dns}"
            }
          catch (err) {
              currentBuild.result = 'FAILURE'
              emailExtraMsg = "Build Failure:"+ err.getMessage()
              throw err
          }
        }
      }
    }
    stage('Get Node Number/Add to Host file') {
      when {  expression { (params.custom_node_name==null || params.custom_node_name.isEmpty()) && ! params.custom_node_check} }
      steps {
        script {
          try {
            node_dns = sh script:"""#!/bin/bash
              source ./script/aerospike_add_node.sh
              add_node_in_ansible_inventory
              """, returnStdout: true
              println "Agent info within script: ${node_dns}"
            }
          catch (err) {
              currentBuild.result = 'FAILURE'
              emailExtraMsg = "Build Failure:"+ err.getMessage()
              throw err
          }
        }
      }
    }
    stage('Launch new Instance && Create New Record') {
      steps {
        script {
          try {
            sh """#!/bin/bash
            source ./script/aerospike_add_node.sh
            create_instance_and_dns_record \$(echo "${node_dns}")         
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
    stage('Deploying aerospike Container') {
      steps {
          script {
                sh  """
                set -x  
                instance_dns=\$(echo "${node_dns}")
                cd ansible
                ansible-playbook -i inventories/${inventory_env} deploy-docker-compose.yaml -e 'ansible_ssh_user=ec2-user' --ssh-common-args='-o StrictHostKeyChecking=no' --ssh-common-args='-o StrictHostKeyChecking=no' --limit "\${instance_dns}"
                """
            }
        }
    }

    stage('Deploying filebeat Container') {
      steps {
          script {
                sh  """
                set -x  
                instance_dns=\$(echo "${node_dns}")
                cd ansible
                ansible-playbook -i inventories/${inventory_env} filebeat-deploy.yaml -e 'ansible_ssh_user=ec2-user' --ssh-common-args='-o StrictHostKeyChecking=no' --ssh-common-args='-o StrictHostKeyChecking=no' --limit "\${instance_dns}"
                """
            }
        }
    }

    stage('Deploying aerospike-exporter Container') {
      steps {
          script {
                sh  """
                set -x  
                instance_dns=\$(echo "${node_dns}")
                cd ansible
                ansible-playbook -i inventories/${inventory_env} install-aerospike-exporter.yaml -e 'ansible_ssh_user=ec2-user' --ssh-common-args='-o StrictHostKeyChecking=no' --ssh-common-args='-o StrictHostKeyChecking=no' --limit "\${instance_dns}"
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
                git commit -m "Added Node with jenkins build # ${currentBuild.number} aerospike node DNS ${node_dns}"
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
            slackSend color: "good", channel: "zypmedia-spotinst-deployment", message: "Jenkins Aerospike Add Node Pipeline Ran Successfully \n JOB NAME:- ${env.JOB_NAME}\n BUILD NUMBER # ${env.BUILD_NUMBER}\n BUILD-URL:-${env.BUILD_URL}"
          } 
      }
      failure {  
        script {
            slackSend color: "danger", channel: "zypmedia-spotinst-deployment", message: "Jenkins Aerospike Add Node Pipeline Failed \n JOB NAME:- ${env.JOB_NAME}\n BUILD NUMBER # ${env.BUILD_NUMBER}\n BUILD-URL:-${env.BUILD_URL}"
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