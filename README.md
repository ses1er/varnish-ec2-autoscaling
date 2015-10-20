This script will generate a round-robin backend director based on EC2 tag name and value, useful for backends in an austoscaling group. If the newly generated vcl is different than the current running one, the old one will be overwritten and varnish_reload_vcl will be executed.


Dependencies
 
 -> aws-cli - environment variables must be set for AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY, or have IAM
              role with the following permission: "ec2:Describe*"
 -> md5sum - can easily be installed via system package management, yum or apt-get
 -> varnish 4.0 - this is obvious, but make sure it is working without this script first.
 -> RELOAD_VCL=1 - ensure RELOAD_VCL=1 exists in your varnish.params file.

 This script should be ran as a cron job. Ensure you include the following to your default vcl:
```
 vcl 4.0
 import directors;
 include "<value of $VCL>";

 sub vcl_init {
   call <value of $SUBNAME>;
}
```
