# auto
## Author
  Wang Chen <wang.chen@zoho.com>
  Editor: thien

# Installation
      cd ~
      git clone https://github.com/wang-chen/auto.git
      cd auto
      ./install.sh
      
## Usage
  After installation, please find the file in your home folder "~/auto/myros.sh".
  Then change the catkin workspace name according to your own workspace in your home folder, such as:
  
    ROS_CATKINWS_NAME='catkin_ws'
    ROS_BUILDWS_NAME='build_ws'
    
  Then, open a new terminal, enjoy it!

## This repo is for auto user configuration, including:
  ROS indigo/kinetic environment
  
## GIT bash environment
  your git command environment will be very user-friendly.
  
## Fast command for "catkin_make" and "catkin build". 
  you can use the command "ck" or "CK" (`catkin_make`) and "ckb" or "CKB" (`catkin build`) in any directory to compile your ROS `catkin_make` or `catkin build` workspace, respectively.
      
## Persistent names for ftdi-usb-serial devices. 
  After installation, any FTDI-based usb devices will appear in /dev/sensors/ftdi_[\*\*\*\*] with authority level [666].
  The [\*\*\*\*] will be replaced by the uqiue serial NO. of chips.
  This will speed up your experiments.
  
### Acknoledgement: Chen Chun-lin
