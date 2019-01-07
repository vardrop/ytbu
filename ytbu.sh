#!/bin/bash
#note I use a lot of functions since I can fold and move them around easily
##############################LOCK FILE############################## https://stackoverflow.com/a/25243837/7157385
SCRIPTNAME=$(basename $0)
LOCKDIR="/var/lock/${SCRIPTNAME}"
PIDFILE="${LOCKDIR}/pid"

if ! mkdir $LOCKDIR 2>/dev/null
then
    # lock failed, but check for stale one by checking if the PID is really existing
    PID=$(cat $PIDFILE)
    if ! kill -0 $PID 2>/dev/null
    then
       echo "Removing stale lock of nonexistent PID ${PID}" >&2
       rm -rf $LOCKDIR
       echo "Restarting myself (${SCRIPTNAME})" >&2
       exec "$0" "$@"
    fi
    echo "$SCRIPTNAME is already running, bailing out" >&2
    exit 1
else
    # lock successfully acquired, save PID
    echo $$ > $PIDFILE
fi

trap "rm -rf ${LOCKDIR}" QUIT INT TERM EXIT
##############################FUNCTIONS##############################
ytbu_err() { # any error and help ends here
  echo Normal usage: 'bash ytbu.sh'
  echo Quickstart: 'sudo bash ytbu.sh go'
  echo Only install dependencies: 'bash ytbu.sh install'
  echo Only configure: 'bash ytbu.sh config'
  echo Run normally: 'bash ytbu.sh'
  echo Guide for retriving your client_secret.json: 'bash ytbu.sh secret'
  echo "For more information about configuration see https://github.com/pyptq/ytbu"
  exit 1
}
ytbu_secret() { # just a guide for setup
  echo To retrive your client_secret.json open:
  echo https://console.developers.google.com/apis/credentials?project=_
  echo If you don't have one, create a project.
  echo Under APIs enable Youtube Data APIv3.
  echo Go to credentials page under APIs & Services.
  echo Ensure, that at the top left your project is selected.
  echo Click on 'OAuth consent screen' in the top bar, enter a name and at the bottom, click Save.
  echo Again on the Credentials screen press 'Create credentials', 'OAuth client ID', 'Other'
  echo Enter a name for the backup app, click 'Create'.
  echo You will be presented with your client ID and your client secret. Close that.
  echo Under 'OAuth 2.0 client IDs' you will find the client you just created.
  echo On the far right there is a download button. Click that.
  echo Rename the downloaded file to client_secret.json and move it to ytbu's working directory.
}
test_sudo() {
  if ! command -v sudo>/dev/null; then
    echo "ERR: You need root to install dependencies!"
    ytbu_err
  fi
}
ytbu_install() {
  test_sudo #check for sudo (code from id.ee)
  sudo apt update
  sudo apt install ffmpeg python3 python3-pip curl wget -y
  #Download youtube-dl
  sudo curl -L https://yt-dl.org/downloads/latest/youtube-dl -o /usr/local/bin/youtube-dl
  #Mark youtube-dl executable
  sudo chmod a+rx /usr/local/bin/youtube-dl
  # Install python script dependencies
  sudo pip3 install --upgrade google-api-python-client google-auth google-auth-oauthlib google-auth-httplib2 oauth2client
  echo Dependencies installed!
}
datamonster () {
#Repetitive checking needs less code when using functions
#get subscriptions from google, using python version as it was the fastest (and only) I could get working with the API
$py3 $wdir/ytbu_getdata.py --noauth_local_webserver | tee $wdir/.ytbu_tmp_data.txt
#filter newest data and append to the channel list
cat $wdir/.ytbu_tmp_data.txt | grep -o "'channelId': '[a-zA-Z0-9_-]*" | sed "s#^.*'#https://www.youtube.com/channel/#" | grep -v $ownid >> $wdir/ytbu_channels.txt
# Check if there is any more pages (checks if there is a token for next page) (api can get only 50 subscriptions once)
checknextempty=$(cat $wdir/.ytbu_tmp_data.txt | grep -o "'nextPageToken': '[a-zA-Z0-9_-]*" | sed "s#^.*'##" )
}
ytbu_channelsget(){
  $py3 ytbu_getownid.py | tee $wdir/.ytbu_tmp_ownid
  ownid=$(cat $wdir/.ytbu_tmp_ownid | grep -o "'id': '[a-zA-Z0-9_-]*" | sed "s#^.*'##")
  datamonster #get data
  while ! [ "$checknextempty" = "" ]; do # if you have more than 50 subscribed
  cat $wdir/.ytbu_tmp_data.txt | grep -o "'nextPageToken': '[a-zA-Z0-9_-]*" | sed "s#^.*'##" | sed -e "s@^@nextpagevar='@" -e "s@\$@'@" > $wdir/.ytbu_tmp_nextpager.py # give next page token to python
  datamonster # get more data
done # and loop if there is even more data
}
ytbu_config_wdir(){
  reader=1
  while [[ $reader == 1 ]]; do
    wdir=$PWD
    echo Current working directory is $wdir
    read -p "Change it? " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      read -p "What do you want to change it to? (full directory path, DO NOT END WITH A SLASH!): " -r
      wdir=$REPLY
      reader=0
    elif [[ $REPLY =~ ^[Yy]$ ]]; then
      reader=0
    else
      echo What?
      reader=1
    fi
  done
}
ytbu_config_webhooky(){
  reader=1
  while [[ $reader == 1 ]]; do
    read -p "Use webhooks to notify: OAuth token expired ? " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      webhooky_oauth=1
      reader=0
    elif [[ $REPLY =~ ^[Yy]$ ]]; then
      webhooky_oauth=0
      reader=0
    else
      echo What?
      reader=1
    fi
  done
  reader=1
  while [[ $reader == 1 ]]; do
    read -p "Use webhooks to notify: ytbu run completed ? " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      webhooky_complete=1
      reader=0
    elif [[ $REPLY =~ ^[Yy]$ ]]; then
      webhooky_complete=0
      reader=0
    else
      echo What?
      reader=1
    fi
  done
  if [[ "$webhooky_oauth" = 1 ]] || [[ $webhooky_complete = 1 ]]; then #
    read -p "Enter an url to make a post request to: " -r
    webhooky_token=$REPLY
  else
    :
  fi
}
ytbu_config_installcheck(){
  #set defaults
  py3="/usr/bin/python3"
  ydl="/usr/local/bin/youtube-dl"
  reader=1
  while [[ $reader == 1 ]]; do
    if $py3 --version; then #check if default works
      reader=0
    else
      echo python3 not detected/installed!
      echo r - retry, check again
      echo c - change path to python3
      echo x - exit
      echo
      echo If you see something with /bin/python, change the path to it:
      whereis python3 #look for python3
      read -p "" -n 1 -r
      echo
      replyz=$REPLY #changing reply, since it will be overwritten when changing path
      if [[ $replyz =~ ^[Rr]$ ]]; then
        :#retry
        readerz=1
      elif [[ $replyz =~ ^[Cc]$ ]]; then
        read -p "full path to python3: " -r #change path
        py3=$REPLY
        readerz=1
      elif [[ $replyz =~ ^[Xx]$ ]]; then
        echo ERR: python3 not detected!
        ytbu_err
      else
        echo What?
        readerz=1
      fi
      reader=1
    fi
  done
  reader=1 #once again, but for youtube-dl instead of python3
  while [[ $reader == 1 ]]; do
    if $ydl --version; then
      reader=0
    else
      echo youtube-dl not detected/installed!
      echo r - retry, check again
      echo c - change path to python3
      echo x - exit
      echo
      echo If you see something with /bin/youtube-dl, change the path to it:
      whereis youtube-dl
      read -p "" -n 1 -r
      echo
      replyz=$REPLY
      if [[ $replyz =~ ^[Rr]$ ]]; then
        :
        readerz=1
      elif [[ $replyz =~ ^[Cc]$ ]]; then
        read -p "full path to youtube-dl: " -r
        py3=$REPLY
        readerz=1
      elif [[ $replyz =~ ^[Xx]$ ]]; then
        echo ERR: python3 not detected!
        ytbu_err
      else
        echo What?
        readerz=1
      fi
      reader=1
    fi
  done
}
ytbu_configure(){ #run functions and save the final config


  ytbu_config_installcheck
  ytbu_config_wdir
  ytbu_config_webhooky
  echo $wdir $webhooky_oauth $webhooky_complete $webhooky_token
  echo "Configuration complete!"
}

##############################CHECK ARGUMENTS##############################
# check if any arguments were passed
ytbu_main_args(){
  if [ "$1" = "" ]; then
    ytbu_main
  elif [ "$1" = "install" ]; then
    ytbu_install
    exit
  elif [ "$1" = "go"]; then
    ytbu_secret
    ytbu_install
    ytbu_configure
    read -n1 -r -p "If you have your client_secret.json in the working directory, press any key to continue..." key
    ytbu_main
  elif [ "$1" = "configure" ]; then
    ytbu_configure
    exit
  elif [ "$1" = "secret" ]; then
    ytbu_secret
    exit
  elif [ "$1" = "help" ]; then
    ytbu_err
  else
    echo ERR: Invalid argument!
    ytbu_err
  fi
}
ytbu_main_args #folding is great
##MAIN##
ytbu_main(){
if [ ! -f ./ytbu.cfg ]; then
  echo ERR: No configuration set!
  ytbu_err
fi
source ./ytbu.cfg # Read aliases from file
cd $wdir #incase if all else fails
if [ ! -f $wdir/client_secret.json ]; then
  echo ERR: No client_secret.json found!
  ytbu_err
fi
rm -f $wdir/.ytbu_tmp_nextpager.py $wdir/ytbu_channels.txt # clean up from previous run
ytbu_channelsget # Get a list of channels
}





#OLD stuff below
ytbu_downloadfiles () {
$ydl --download-archive $wdir/ytbu_downloaded.txt -i -o "$wdir/ytbu_downloaded/%(uploader)s/%(upload_date)s-%(id)s.%(ext)s" -f bestvideo+bestaudio --batch-file $wdir/ytbu_channels.txt
echo all downloaded
}
#
# Choose what to do with downloaded files:
ytbu_sendfiles () {
    #If you want to do nothing to the files and leave them in the working directory, do nothing.
    #If you want to move the files locally to somewhere else, change the destination and uncomment the line below.
      #mv $wdir/dowloaded/* /your/destination
    #If you want to move the files offsite, uncomment the line below, change the remote's name, path and add an rclone.config to your working directory.
      #rcl $wdir/downloaded/ remote: --config $wdir/rclone.config
echo ytbu run finished
}
#
#
#End of config area
##############################MAIN SCRIPT##############################

# Chek if this machine is the primary node
if [ $node = 1 ]
then
#Cleanup previous run files
rm -f $wdir/ytbu_master_new.txt $wdir/ytbu_node_*_new.txt
# Make a list of videos that need to be downloaded
$ydl -j --flat-playlist --batch-file $wdir/ytbu_channels.txt --download-archive $wdir/ytbu_downloaded.txt | jq -r '.id' | sed 's_^_https://youtu.be/_' > $wdir/ytbu_master/ytbu_master_new.txt
elif [ $node = 0 ]
then
echo slave
else
echo ERROR: Check node value in ytbu.sh!
exit 1
fi
#Download everything new
ytbu_downloadfiles
# Transfer files: call a function
ytbu_sendfiles
