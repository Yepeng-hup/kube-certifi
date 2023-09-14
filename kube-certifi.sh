#!/bin/bash
# user: yp
# datetime: 2023/9/13

FUNC=$1
CERTS_NAME=$2
CERTIFICATE_DIR=/opt/certs
RED=31; GREEN=32; YELLOW=33; BLUE=34; WHITE=37
FG=****************************************************************************************************************************
HOST=()

if [ ! -d ${CERTIFICATE_DIR} ];then
    mkdir -p ${CERTIFICATE_DIR}
fi

if [ ! -f kubelet.txt ];then
    touch kubelet.txt
fi

if [ ! -f apiserver.txt ];then
    touch apiserver.txt
fi

if [ ! -f etcd.txt ];then
    touch etcd.txt
fi

if [ ! -f coutom.txt ];then
    touch coutom.txt
fi


function add-host-group(){
    while IFS= read -r ip
    do
        HOST+=("$ip")
    done < "$1"
}


function check(){
    if [ `echo "$?"` -ne "0" ];then
        printf "\033[${RED}mERROR: ${1}\033[0m\n"
        exit 1
    fi
}


function check-ca(){
    ls ${CERTIFICATE_DIR}/ca-key.pem > /dev/null 2>&1
    check "没有检查到CA证书,请生成CA证书."
}


function check-file-format(){
    if grep -q '^$' "$1";then
        printf "\033[${RED}mERROR: ${1}文件格式不通过,不允许有空行.\033[0m\n"
        exit 1 
    fi
}


function install-cfssl(){
    wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 -O /usr/bin/cfssl --no-check-certificate >& /dev/null && \
    wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 -O /usr/bin/cfssl-json --no-check-certificate >& /dev/null && \
    wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64 -O /usr/bin/cfssl-certinfo --no-check-certificate 
    if [ `echo "$?"` -ne "0" ];then
        printf "\033[${RED}mERROR: cfssl 安装失败,请检查主机网络.\033[0m\n"
        exit 1
    else
        printf "\033[${GREEN}mINFO: cfssl 安装成功.\033[0m\n"
    fi
    chmod +x /usr/bin/cfssl*
}

function install-jq(){
    yum -y install epel-release >& /dev/null && yum -y install jq >& /dev/null
    if [ `echo "$?"` -ne "0" ];then
        printf "\033[${RED}mERROR: jq 安装失败,请检查yum源.\033[0m\n"
        exit 1
    fi
}


function if-command(){
    cfssl version >& /dev/null
    if [ `echo "$?"` -ne "0" ];then
        printf "\033[${RED}mERROR: 没有cfssl命令.\033[0m\n"
        read -p "是否安装cfssl [y/n]: " X
        if [ $X == 'y' ];then
            install-cfssl
        else
            exit 1
        fi
    fi
    jq -h >& /dev/null || install-jq
}
if-command


function create-CaFile(){
    printf "\033[${YELLOW}mINFO: 开始生成CA证书\033[0m\n"
cat > $CERTIFICATE_DIR/ca-csr.json << emo
{
    "CN": "k8sEdu",
    "hosts": [
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "hangzhou",
            "ST": "zhejiang",
            "O": "b"
        }
    ]
}
emo

cat > $CERTIFICATE_DIR/ca-config.json << emo
{
    "signing": {
        "default": {
            "expiry": "876000h"
        },
        "profiles": {
            "www": {
                "expiry": "876000h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth"
                ]
            },
            "client": {
                "expiry": "876000h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "client auth"
                ]
            }
        }
    }
}
emo

    check "cfssl 生成配置失败"
    cd $CERTIFICATE_DIR
    cfssl gencert -initca ca-csr.json | cfssl-json -bare ca
    check "cfssl 证书生成失败,请检查json文件"
    local certs=$(ls ca*)
    printf "\033[${YELLOW}mINFO: CA签发成功,证书如下\033[0m\n"
    for i in $certs
    do
        echo "$i"
    done
    echo " "
    echo -e  "\033[${BLUE}m${FG}\033[0m\n"
    echo " "
}


function kube-etcd-colony(){
    check-ca
    check-file-format "etcd.txt"
    add-host-group "etcd.txt"
    printf "\033[${YELLOW}mINFO: 开始生成etcd colony证书\033[0m\n"
cat > $CERTIFICATE_DIR/ca-config.json << emo
{
    "signing": {
        "default": {
            "expiry": "876000h"
        },
        "profiles": {
            "server": {
                "expiry": "876000h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth"
                ]
            },
            "client": {

                "expiry": "876000h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "client auth"
                ]
            },
            "peer": {
                 "expiry": "876000h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
             }
        }
    }
}
emo

# hosts这里是你要在那机台服务器上部署etcd集群
cat > $CERTIFICATE_DIR/etcd-peer-csr.json << emo
{
    "CN": "k8s-etcd",
    "hosts": $(printf '%s\n' "${HOST[@]}" | jq -R . | jq -s .),
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "hangzhou",
            "ST": "zhejiang",
            "O": "b"
        }
    ]
}
emo
    check "cfssl 生成配置失败"
    cd $CERTIFICATE_DIR
    cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=peer etcd-peer-csr.json | cfssl-json -bare etcd-peer
    check "cfssl 证书生成失败,请检查json文件"
    local certs=$(ls etcd*)
    printf "\033[${YELLOW}mINFO: ETCD签发成功,证书如下\033[0m\n"
    for i in $certs
    do
        echo "$i"
    done
    echo " "
    echo -e  "\033[${BLUE}m${FG}\033[0m\n"
    echo " "
}

function client_all(){
    check-ca
    printf "\033[${YELLOW}mINFO: 开始生成k8s-colony client all证书\033[0m\n"
cat > $CERTIFICATE_DIR/client-csr.json << emo
{
    "CN": "k8s-node",
    "hosts": [
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "hangzhou",
            "ST": "zhejiang"
        }
    ]
}
emo
    check "cfssl 生成配置失败"
    cd $CERTIFICATE_DIR
    cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=client client-csr.json | cfssl-json -bare client
    check "cfssl 证书生成失败,请检查json文件"
    local certs=$(ls client*)
    printf "\033[${YELLOW}mINFO: client签发成功,证书如下\033[0m\n"
    for i in $certs
    do
        echo "$i"
    done
    echo " "
    echo -e  "\033[${BLUE}m${FG}\033[0m\n"
    echo " "
}


function kube-apiserver(){
    check-ca
    check-file-format "apiserver.txt"
    add-host-group "apiserver.txt"
    printf "\033[${YELLOW}mINFO: 开始生成apiserver证书\033[0m\n"
#//host is node-network pod-network localhost corednsIP vm-vip ...
cat > $CERTIFICATE_DIR/apiserver-csr.json << emo
{
    "CN": "k8s-apiserver",
    "hosts": $(printf '%s\n' "${HOST[@]}" | jq -R . | jq -s .),
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "hangzhou",
            "ST": "zhejiang"
        }
    ]
}
emo
    check "cfssl 生成配置失败"
    cd $CERTIFICATE_DIR
    cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=server apiserver-csr.json | cfssl-json -bare apiserver
    check "cfssl 证书生成失败,请检查json文件"
    local certs=$(ls apiserver*)
    printf "\033[${YELLOW}mINFO: kube-apiserver签发成功,证书如下\033[0m\n"
    for i in $certs
    do
        echo "$i"
    done
    echo " "
    echo -e  "\033[${BLUE}m${FG}\033[0m\n"
    echo " "
}


function kube-ControllerManager(){
    check-ca
    printf "\033[${YELLOW}mINFO: 开始生成ControllerManager证书\033[0m\n"
cat > $CERTIFICATE_DIR/kube-controller-manager-csr.json << emo
{
  "CN": "system:kube-controller-manager",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "L": "hang zhou",
      "ST": "zhe jiang",
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
emo
    check "cfssl 生成配置失败"
    cd $CERTIFICATE_DIR
    cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=client kube-controller-manager-csr.json | cfssl-json -bare kube-controller-manager-client
    check "cfssl 证书生成失败,请检查json文件"
    local certs=$(ls kube-controller-manager*)
    printf "\033[${YELLOW}mINFO: kube-ControllerManager client 签发成功,证书如下\033[0m\n"
    for i in $certs
    do
        echo "$i"
    done
    echo " "
    echo -e  "\033[${BLUE}m${FG}\033[0m\n"
    echo " "
}


function kube-schedul(){
    check-ca
    printf "\033[${YELLOW}mINFO: 开始生成schedul证书\033[0m\n"
cat > $CERTIFICATE_DIR/kube-scheduler-csr.json << emo
{
  "CN": "system:kube-scheduler",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "L": "hang zhou",
      "ST": "zhe jiang",
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
emo
    check "cfssl 生成配置失败"
    cd $CERTIFICATE_DIR
    cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=client kube-scheduler-csr.json | cfssl-json -bare kube-scheduler-client
    check "cfssl 证书生成失败,请检查json文件"
    local certs=$(ls kube-scheduler*)
    printf "\033[${YELLOW}mINFO: kube-scheduler client 签发成功,证书如下\033[0m\n"
    for i in $certs
    do
        echo "$i"
    done
    echo " "
    echo -e  "\033[${BLUE}m${FG}\033[0m\n"
    echo " "
}


function kubectls(){
    check-ca
    printf "\033[${YELLOW}mINFO: 开始生成admin client证书\033[0m\n"
cat > $CERTIFICATE_DIR/admin-kubectl-client-csr.json << emo
{
    "CN": "admin",
    "hosts": [
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "hang zhou",
            "ST": "zhe jiang",
            "O": "system:masters",
            "OU": "System"
        }
    ]
}
emo
    check "cfssl 生成配置失败"
    cd $CERTIFICATE_DIR
    cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=client admin-kubectl-client-csr.json | cfssl-json -bare admin-client
    check "cfssl 证书生成失败,请检查json文件"
    local certs=$(ls admin*)
    printf "\033[${YELLOW}mINFO: admin client 签发成功,证书如下\033[0m\n"
    for i in $certs
    do
        echo "$i"
    done
    echo " "
    echo -e  "\033[${BLUE}m${FG}\033[0m\n"
    echo " "
}


function kubelets(){
    check-ca
    check-file-format "kubelet.txt"
    add-host-group "kubelet.txt"
    printf "\033[${YELLOW}mINFO: 开始生成kubelet证书\033[0m\n"
#hosts is nodeIp
cat > $CERTIFICATE_DIR/kubelet-csr.json << emo
{
   "CN": "k8s-kubelet",
   "hosts": $(printf '%s\n' "${HOST[@]}" | jq -R . | jq -s .),

   "key": {
        "algo": "rsa",
        "size": 2048
   },

   "names": [
        {
          "C": "CN",
          "ST": "zhejiang",
          "L": "hangzhou",
          "OU": "System"
     }
   ]

}
emo
    check "cfssl 生成配置失败"
    cd $CERTIFICATE_DIR
    cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=server kubelet-csr.json | cfssl-json -bare kubelet
    check "cfssl 证书生成失败,请检查json文件"
    local certs=$(ls kubelet*)
    printf "\033[${YELLOW}mINFO: kubelet server 签发成功,证书如下\033[0m\n"
    for i in $certs
    do
        echo "$i"
    done
    echo " "
    echo -e  "\033[${BLUE}m${FG}\033[0m\n"
    echo " "   
}

function kube-proxys(){
    check-ca
    printf "\033[${YELLOW}mINFO: 开始生成kube-proxy证书\033[0m\n"
# k8s里的角色
cat >$CERTIFICATE_DIR/kube-proxy-csr.json << emo
{
    "CN": "system:kube-proxy",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "hangzhou",
            "ST": "zhejiang",
            "OU": "System"
        }
    ]
}
emo
    check "cfssl 生成配置失败"
    cd $CERTIFICATE_DIR
    cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=client kube-proxy-csr.json | cfssl-json -bare kube-proxy-client
    check "cfssl 证书生成失败,请检查json文件"
    local certs=$(ls kube-proxy*)
    printf "\033[${YELLOW}mINFO: kube-proxy client 签发成功,证书如下\033[0m\n"
    for i in $certs
    do
        echo "$i"
    done
    echo " "
    echo -e  "\033[${BLUE}m${FG}\033[0m\n"
    echo " "
}


function create_other_ClientCerts(){
    check-ca
    local assembly_name=$1
    printf "\033[${YELLOW}mINFO: 开始生成 ${assembly_name} 证书\033[0m\n"
cat > $CERTIFICATE_DIR/${assembly_name}-client-csr.json << emo
{
    "CN": "${assembly_name}",
    "hosts": [
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "hangzhou",
            "ST": "zhejiang"
        }
    ]
}
emo
    check "cfssl 生成配置失败"
    cd $CERTIFICATE_DIR
    cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=client ${assembly_name}-csr.json | cfssl-json -bare ${assembly_name}-client
    check "cfssl 证书生成失败,请检查json文件"
    local certs=$(ls ${assembly_name}*)
    printf "\033[${YELLOW}mINFO: ${assembly_name}签发成功,证书如下\033[0m\n"
    for i in $certs
    do
        echo "$i"
    done
    echo " "
    echo -e  "\033[${BLUE}m${FG}\033[0m\n"
    echo " "
}


function create_other_ServerCerts(){
    check-ca
    check-file-format "coutom.txt"
    add-host-group "coutom.txt"
    local assembly_name=$1
    printf "\033[${YELLOW}mINFO: 开始生成 ${assembly_name} 证书\033[0m\n"
cat > $CERTIFICATE_DIR/${assembly_name}-server-csr.json << emo
{
    "CN": "${assembly_name}",
    "hosts": $(printf '%s\n' "${HOST[@]}" | jq -R . | jq -s .),
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "hangzhou",
            "ST": "zhejiang"
        }
    ]
}
emo
    check "cfssl 生成配置失败"
    cd $CERTIFICATE_DIR
    cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=server ${assembly_name}-csr.json | cfssl-json -bare ${assembly_name}-server
    check "cfssl 证书生成失败,请检查json文件"
    local certs=$(ls ${assembly_name}*)
    printf "\033[${YELLOW}mINFO: ${assembly_name}签发成功,证书如下\033[0m\n"
    for i in $certs
    do
        echo "$i"
    done
    echo " "
    echo -e  "\033[${BLUE}m${FG}\033[0m\n"
    echo " "
}

case $FUNC in
    ca)
    create-CaFile;;
    etcd-colony)
    kube-etcd-colony;;
    client)
    client_all;;
    kube-apiserver)
    kube-apiserver;;
    controller)
    kube-ControllerManager;;
    schedul)
    kube-schedul;;
    kubectl)
    kubectls;;
    kubelet)
    kubelets;;
    proxy)
    kube-proxys;;
    set-client)
    create_other_ClientCerts $CERTS_NAME;;
    set-server)
    create_other_ServerCerts $CERTS_NAME;;
    *)
    printf "\033[${RED}m$0 and (ca|etcd-colony|client|kube-apiserver|controller|schedul|kubectl|kubelet|proxy|set-client(后面要加参数)|set-server(后面要加参数))\033[0m\n"
esac