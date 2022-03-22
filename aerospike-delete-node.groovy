def nodeip = ''
def ec2_node_name=''
pipeline {
  agent any
    parameters {
            string(defaultValue: '', name: 'NODE_NAME', trim: true)
        }
    stages {
      stage('Get Last Node of Cluster') {
        when {  expression { params.NODE_NAME.isEmpty() } }
        steps {
            script {
                try {
                    ec2_node_name = sh script:"""#!/bin/bash
                    source ./script/aerospike_delete_node.sh
                    get_last_node_metadata
                    """, returnStdout: true
                    println "Agent info within script: ${ec2_node_name}"
                }
                catch (err) {
                    currentBuild.result = 'FAILURE'
                    emailExtraMsg = "Build Failure:"+ err.getMessage()
                    throw err
                }
              }
          }
        }
      stage('Get Node of Cluster') {
        when { expression { !params.NODE_NAME.isEmpty()  } }
        steps {
            script {
                echo "************Get Node of Cluster************"
                try {
                      ec2_node_name = sh script:"""#!/bin/bash
                      source ./script/aerospike_delete_node.sh
                      get_node_name
                      """, returnStdout: true
                      println "Agent info within script: ${ec2_node_name}"
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
                    extract_ip_of_last_node \$(echo "${ec2_node_name}")
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
 
}
      }
