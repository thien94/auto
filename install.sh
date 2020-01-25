#!/bin/bash
echo "Installing..."
echo "Author Jeffsan Chen Wang: jeffsan.wang@gmail.com"
sudo cp rules/*  /etc/udev/rules.d/
sudo cat ./.bashrc >> ~/.bashrc
echo "done."
