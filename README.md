# Kubernetes for RightScale

## Self-Service CAT, ServerTemplate, and RightScripts

### Instructions

#### ServerTemplate and RightScripts

* Install the RightScale [right_st tool](https://github.com/rightscale/right_st)
* Configure right_st using [these instructions](https://github.com/rightscale/right_st#configuration)
* From the root of this repo, run `right_st st upload Kubernetes.yml`

#### MultiCloud Image for Ubuntu 15.10 Wily

* Clone the MCI from [https://www.rightscale.com/library/multi_cloud_images/Ubuntu_14-04_x64/lineage/53873](https://www.rightscale.com/library/multi_cloud_images/Ubuntu_14-04_x64/lineage/53873)

* Rename the MCI to `Ubuntu Wily RL10`

* Replace the MCI's GCE image with the latest variation of `ubuntu-1510-wily-v20160405`

* Commit the MCI until you have a version `2`

#### Self-Service CAT

* [Upload](http://docs.rightscale.com/ss/guides/ss_testing_CATs.html) and [Publish](http://docs.rightscale.com/ss/guides/ss_publishing_CATs.html) the CAT in Self-Service

* Instructions for using the CAT will be shown when pressing the Details button from the CloudApp's preview on the Catalog screen.
