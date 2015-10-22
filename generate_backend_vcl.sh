#!/bin/bash
#
# This script will generate a backend round-robin director based on EC2 tag name/value, useful for backends
# in an austoscaling group. If the newly generated vcl is different than the current running one, the
# old one will be overwritten and varnish_reload_vcl will be executed.
#
#
# Dependencies
# -> aws-cli - environment variables must be set for AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY, or have IAM
#              role with the following permission: "ec2:Describe*"
# -> md5sum - can easily be installed via system package management, yum or apt-get
# -> varnish 4.0 - this is obvious, but make sure it is working without this script first.
# -> RELOAD_VCL=1 - ensure RELOAD_VCL=1 exists in your varnish.params file.
#
# This script should be ran as a cron job. Ensure you include the following to your default vcl:
#
# vcl 4.0
# import directors;
# include "<value of $VCL>";
#
# sub vcl_init {
#   call <value of $SUBNAME>;
# }
#
# USER DEFINED VARIABLES:
#
# Region for aws-cli
REGION="us-east-1"
# Tag name to be used as a filter
TAGNAME="varnish-backend"
# Tag value to be used as a filter
TAGVALUE="backend"
# Alias for each backend, it will be appended with an index number
BACKEND=$TAGVALUE
# Alias for the director
DIRECTOR=$TAGVALUE
# Name for the function, need to add to sub vcl_init in your default vcl
SUBNAME="$TAGVALUE_init"
# Temporary VCL location
TEMPVCL="/tmp/backends.vcl"
# Default VCL location
VCL="/etc/varnish/backends.vcl"
# Probes to include, will only add if file exists
PROBE="/etc/varnish/probe"
# Backend port to be used
BEPORT="80"

# SHOULD NOT HAVE TO MODIFY BELOW
#######################################
#
# Quick dependency check...
#
if [ ! `which aws` ] &>/dev/null; then
  echo "AWS CLI tool not found in your PATH! exiting"
  exit 1
fi

if [ ! `which md5sum` ] &>/dev/null; then
  echo "md5sum not found in your PATH! exiting"
  exit 1
fi

if [ ! `which varnish_reload_vcl` ] &>/dev/null; then
  echo "varnish_reload_vcl not found in your PATH! exiting"
  exit 1
fi

# Alright, let's go!

INSTANCE_IPS=$(aws ec2 describe-instances --region $REGION  --filters "Name=tag:$TAGNAME,Values=$TAGVALUE" --query Reservations[].Instances[].PrivateIpAddress --output text|tr "\t" "\n"|sort -n -t . -k 1,1 -k 2,2 -k 3,3 -k 4,4)

INDEX=0
echo "#" > $TEMPVCL
for IP in $INSTANCE_IPS; do
  echo "backend $BACKEND$INDEX {" >> $TEMPVCL
  echo " .host = \"$IP\";" >> $TEMPVCL
  echo " .port = \"$BEPORT\";" >> $TEMPVCL
  if [ -e $PROBE ]; then
    echo " .probe = {" >> $TEMPVCL
    cat $PROBE >> $TEMPVCL
    echo "}" >> $TEMPVCL
  fi
  echo "}" >> $TEMPVCL
  INDEX=$((INDEX+1))
done
echo "sub $SUBNAME {" >> $TEMPVCL
echo "new $DIRECTOR = directors.round_robin();" >> $TEMPVCL
for ((x=0; x<$INDEX; x++)); do
  echo "$DIRECTOR.add_backend($BACKEND$x);" >> $TEMPVCL
done
echo "}" >> $TEMPVCL

MD5NEW=$(md5sum $TEMPVCL|cut -d " " -f 1)
MD5OLD=$(md5sum $VCL|cut -d " " -f 1)

if [ "$MD5NEW" == "$MD5OLD" ]; then
  echo "Varnish config identical, done."
else
  echo "New backend vcl is not identical, replacing $VCL."
  mv $TEMPVCL $VCL
  varnish_reload_vcl
fi
