#!/bin/bash

TRANSCODER_ENABLED=true;
APPLICATION=grpc-quarkus-transcoder;
PROTOBIN_DEST=envoy/proto.pb;

### Build proto service(s) and add each to values.yaml
build_proto_services()
{
  echo "Start build of proto services.."
    export PROTO_SERVICES=()
    for i in $1;
    #for i in $PROTO_PATHS;
      do
        # if the proto file has a service (this is using GNU grep, not OS X grep)
        if [ ! -z "$(cat $i | grep -oP '(?<=(^service) )[^ ]*')" ]; then
    
          # retrieve package name and replace semicolon with period
          export PROTO_PACKAGE=$(cat $i | grep -oP '(?<=(^package) )[^ ]*' | sed 's/;/./g')
    
          # retrieve service name 
          export PROTO_SERVICE_NAME=$(cat $i | grep -oP '(?<=(^service) )[^ ]*')
    
          # build list and apply services to values.yaml in gitops repository
          if [ ${#PROTO_SERVICES[@]} == 0 ]; then
            yq eval '.quarkus-service.serviceMesh.transcoder.services = ["'"$PROTO_PACKAGE$PROTO_SERVICE_NAME"'"]' --inplace values.yaml
            PROTO_SERVICES+=("$PROTO_PACKAGE$PROTO_SERVICE_NAME")
          else
            yq eval '.quarkus-service.serviceMesh.transcoder.services += ["'"$PROTO_PACKAGE$PROTO_SERVICE_NAME"'"]' --inplace values.yaml
            PROTO_SERVICES+=("$PROTO_PACKAGE$PROTO_SERVICE_NAME")
          fi

        fi
      done
}

# task to perform if serviceMesh transcoder is enabled
if [ $TRANSCODER_ENABLED ]
then
  if [ ! -d $APPLICATION ]; then
    ### Clone source repo (this can be any repo, using my hello world as example)
    git clone https://github.com/xbhouse/grpc-quarkus-transcoder
  fi
  
  ### Find proto file paths, excluding google protobufs
  echo "Change to $APPLICATION directory and find proto files.."
  cd $APPLICATION
  export PROTO_PATHS=$(find . -type f -name "*.proto" ! -path "*google/*")
  
  ### Build proto service(s) and add each to values.yaml
  build_proto_services $PROTO_PATHS

  echo "Create directory and file for protobin.."
  ### Create directory and file for protobin 
  if [ ! -d "envoy" ]; then
    mkdir envoy
    touch envoy/proto.pb
  fi

  echo "Generate protobin with current list of proto paths.."
  ### Generate protobin and send output to PROTOBIN_DEST
  protoc -I./src/main/proto --include_imports --include_source_info --descriptor_set_out=$PROTOBIN_DEST $PROTO_PATHS

  echo "Encode protobin.."
  ### Encode protobin and send output to PROTOBIN_DEST.b64
  base64 -i $PROTOBIN_DEST | tr -d '\n\r' > $PROTOBIN_DEST.b64

  echo "Apply encoded protobin to filter.."
  ### Apply encoded protobin to values.yaml
  yq eval '.quarkus-service.serviceMesh.transcoder.encodedProtoBin="'"$(cat $PROTOBIN_DEST.b64)"'"' --inplace ../values.yaml
fi