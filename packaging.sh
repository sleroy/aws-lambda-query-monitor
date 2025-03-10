#!/bin/bash

echo "Executing create_pkg.sh..."
function_name="sqlquery"

path_cwd=.
build_dir=lambda_dist_pkg/
rm $build_dir -Rf
mkdir $build_dir -p

cp -r $path_cwd/lambdas/python/sqlserver/* $path_cwd/$build_dir
# Installing python dependencies...
FILE=$path_cwd/$build_dir/requirements.txt

if [ -f "$FILE" ]; then
  echo "Installing dependencies..."
  pushd .
  cd $path_cwd/$build_dir
  pip install -r requirements.txt -t .
  popd
else
  echo "Error: $FILE does not exist!"
fi

# Create deployment package...
echo "Creating deployment package..."



echo "Finished script execution!"