load ../common

setup () {
    scope standard
    [[ $CH_BUILDER = ch-image ]] || skip 'ch-image only'
}

@test 'ch-image common options' {
    # no common options
    run ch-image storage-path
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output != *'verbose level'* ]]

    # before only
    run ch-image -vv storage-path
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'verbose level: 2'* ]]

    # after only
    run ch-image storage-path -vv
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'verbose level: 2'* ]]

    # before and after; after wins
    run ch-image -vv storage-path -v
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'verbose level: 1'* ]]
}

@test 'ch-image delete' {
    # verify delete/test image doesn't exist
    run ch-image list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output != *"delete/test"* ]]

    # Build image. It's called called delete/test to check ref parsing with
    # slash present.
    ch-image build -t delete/test -f - . << 'EOF'
FROM 00_tiny
EOF
    run ch-image list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"delete/test"* ]]

    # delete image
    ch-image delete delete/test
    run ch-image list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output != *"delete/test"* ]]
}

@test 'ch-image import' {
    # Note: We don't test importing a real image because (1) when this is run
    # during the build phase there aren't any unpacked images and (2) I can't
    # think of a way import could fail that would be real image-specific.

    ## Test image (not runnable)
    fixtures=${BATS_TMPDIR}/import
    rm -Rfv --one-file-system "$fixtures"
    mkdir "$fixtures" \
          "${fixtures}/empty" \
          "${fixtures}/nonempty" \
          "${fixtures}/nonempty/ch" \
          "${fixtures}/nonempty/bin"
    (cd "$fixtures" && ln -s nonempty nelink)
    touch "${fixtures}/nonempty/bin/foo"
    cat <<'EOF' > "${fixtures}/nonempty/ch/metadata.json"
{ "arch": "corn",
  "cwd": "/",
  "env": {},
  "labels": {},
  "shell": [
    "/bin/sh",
    "-c"
  ],
  "volumes": [] }
EOF
    ls -lhR "$fixtures"

    ## Tarballs

    # tarbomb
    (cd "${fixtures}/nonempty" && tar czvf ../bomb.tar.gz .)
    run ch-image import -v "${fixtures}/bomb.tar.gz" imptest
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"importing:    ${fixtures}/bomb.tar.gz"* ]]
    [[ $output != *'layers: single enclosing directory, using its contents'* ]]
    [[ -f "${CH_IMAGE_STORAGE}/img/imptest/bin/foo" ]]
    grep -F '"arch": "corn"' "${CH_IMAGE_STORAGE}/img/imptest/ch/metadata.json"
    ch-image delete imptest

    # non-tarbomb
    (cd "$fixtures" && tar czvf standard.tar.gz nonempty)
    run ch-image import -v "${fixtures}/standard.tar.gz" imptest
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"importing:    ${fixtures}/standard.tar.gz"* ]]
    [[ $output = *'layers: single enclosing directory, using its contents'* ]]
    [[ -f "${CH_IMAGE_STORAGE}/img/imptest/bin/foo" ]]
    grep -F '"arch": "corn"' "${CH_IMAGE_STORAGE}/img/imptest/ch/metadata.json"
    ch-image delete imptest

    # non-tarbomb, but enclosing directory is a standard dir
    (cd "${fixtures}/nonempty" && tar czvf ../tricky.tar.gz bin)
    run ch-image import -v "${fixtures}/tricky.tar.gz" imptest
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"importing:    ${fixtures}/tricky.tar.gz"* ]]
    [[ $output != *'layers: single enclosing directory, using its contents'* ]]
    [[ -f "${CH_IMAGE_STORAGE}/img/imptest/bin/foo" ]]
    grep -F '"arch": null' "${CH_IMAGE_STORAGE}/img/imptest/ch/metadata.json"
    ch-image delete imptest

    # empty, uncompressed tarfile
    (cd "${fixtures}" && tar cvf empty.tar empty)
    run ch-image import -v "${fixtures}/empty.tar" imptest
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"importing:    ${fixtures}/empty.tar"* ]]
    [[ $output = *'layers: single enclosing directory, using its contents'* ]]
    [[ $output = *'warning: no metadata to load; using defaults'* ]]
    grep -F '"arch": null' "${CH_IMAGE_STORAGE}/img/imptest/ch/metadata.json"
    ch-image delete imptest

    ## Directories

    # non-empty directory
    run ch-image import -v "${fixtures}/nonempty" imptest
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"importing:    ${fixtures}/nonempty"* ]]
    [[ $output = *"copying image: ${fixtures}/nonempty -> ${CH_IMAGE_STORAGE}/img/imptest"* ]]
    [[ -f "${CH_IMAGE_STORAGE}/img/imptest/bin/foo" ]]
    grep -F '"arch": "corn"' "${CH_IMAGE_STORAGE}/img/imptest/ch/metadata.json"
    ch-image delete imptest

    # empty directory
    run ch-image import -v "${fixtures}/empty" imptest
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"importing:    ${fixtures}/empty"* ]]
    [[ $output = *"copying image: ${fixtures}/empty -> ${CH_IMAGE_STORAGE}/img/imptest"* ]]
    [[ $output = *'warning: no metadata to load; using defaults'* ]]
    grep -F '"arch": null' "${CH_IMAGE_STORAGE}/img/imptest/ch/metadata.json"
    ch-image delete imptest

    # symlink to directory
    run ch-image import -v "${fixtures}/nelink" imptest
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"importing:    ${fixtures}/nelink"* ]]
    [[ $output = *"copying image: ${fixtures}/nelink -> ${CH_IMAGE_STORAGE}/img/imptest"* ]]
    [[ -f "${CH_IMAGE_STORAGE}/img/imptest/bin/foo" ]]
    grep -F '"arch": "corn"' "${CH_IMAGE_STORAGE}/img/imptest/ch/metadata.json"
    ch-image delete imptest

    ## Errors

    # input does not exist
    run ch-image import -v /doesnotexist imptest
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"error: can't copy: not found: /doesnotexist"* ]]

    # invalid destination reference
    run ch-image import -v "${fixtures}/empty" 'badchar*'
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'error: image ref syntax, char 8: badchar*'* ]]

    # non-empty file that's not a tarball
    run ch-image import -v "${fixtures}/nonempty/ch/metadata.json" imptest
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"error: cannot open: ${fixtures}/nonempty/ch/metadata.json"* ]]

    ## Clean up
    [[ ! -e "${CH_IMAGE_STORAGE}/img/imptest" ]]
    rm -Rfv --one-file-system "$fixtures"
}

@test 'ch-image list' {

    # list all images
    run ch-image list
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"00_tiny"* ]]

    # name does not exist remotely, in library
    run ch-image list doesnotexist:latest
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'in local storage:    no'* ]]
    [[ $output = *'available remotely:  no'* ]]
    [[ $output = *'remote arch-aware:   n/a'* ]]
    [[ $output = *'archs available:     n/a'* ]]

    # tag does not exist remotely, in library
    run ch-image list alpine:doesnotexist
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'in local storage:    no'* ]]
    [[ $output = *'available remotely:  no'* ]]
    [[ $output = *'remote arch-aware:   n/a'* ]]
    [[ $output = *'archs available:     n/a'* ]]

    # name does not exist remotely, not in library
    run ch-image list charliecloud/doesnotexist:latest
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'in local storage:    no'* ]]
    [[ $output = *'available remotely:  no'* ]]
    [[ $output = *'remote arch-aware:   n/a'* ]]
    [[ $output = *'archs available:     n/a'* ]]

    # tag does not exist remotely, not in library
    run ch-image list charliecloud/metadata:doesnotexist
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'in local storage:    no'* ]]
    [[ $output = *'available remotely:  no'* ]]
    [[ $output = *'remote arch-aware:   n/a'* ]]
    [[ $output = *'archs available:     n/a'* ]]

    # in storage, does not exist remotely
    run ch-image list 00_tiny
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'in local storage:    yes'* ]]
    [[ $output = *'available remotely:  no'* ]]
    [[ $output = *'remote arch-aware:   n/a'* ]]
    [[ $output = *'archs available:     n/a'* ]]

    # not in storage, exists remotely, fat manifest exists
    run ch-image list debian:buster-slim
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'in local storage:    no'* ]]
    [[ $output = *'available remotely:  yes'* ]]
    [[ $output = *'remote arch-aware:   yes'* ]]
    [[ $output = *'archs available:     386 amd64 arm/v5 arm/v7 arm64/v8 mips64le ppc64le s390x'* ]]

    # in storage, exists remotely, no fat manifest
    run ch-image list charliecloud/metadata:2021-01-15
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'in local storage:    yes'* ]]
    [[ $output = *'available remotely:  yes'* ]]
    [[ $output = *'remote arch-aware:   no'* ]]
    [[ $output = *'archs available:     unknown'* ]]

    # exists remotely, fat manifest exists, no Linux architectures
    run ch-image list mcr.microsoft.com/windows:20H2
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'in local storage:    no'* ]]
    [[ $output = *'available remotely:  yes'* ]]
    [[ $output = *'remote arch-aware:   yes'* ]]
    [[ $output = *'warning: no valid architectures found'* ]]

    # scratch is weird and tells lies
    run ch-image list scratch
    echo "$output"
    [[ $status -eq 0 ]]
    #[[ $output = *'in local storage:    yes'* ]]  # varies
    [[ $output = *'full remote ref:     registry-1.docker.io:443/library/scratch:latest'* ]]
    [[ $output = *'available remotely:  yes'* ]]
    [[ $output = *'remote arch-aware:   no'* ]]
    [[ $output = *'archs available:     unknown'* ]]
}

@test 'ch-image reset' {
   export CH_IMAGE_STORAGE="$BATS_TMPDIR"/sd-reset

   # Ensure our test storage dir doesn't exist yet.
   [[ -e $CH_IMAGE_STORAGE ]] && rm -Rf --one-file-system "$CH_IMAGE_STORAGE"

   # Put an image innit.
   ch-image pull alpine:3.9
   ls "$CH_IMAGE_STORAGE"

   # List images; should be only the one we just pulled.
   run ch-image list
   echo "$output"
   [[ $status -eq 0 ]]
   [[ $output = "alpine:3.9" ]]

   # Reset.
   ch-image reset

   # Image storage directory should be empty now.
   expected=$(cat <<'EOF'
.:
dlcache
img
ulcache
version

./dlcache:

./img:

./ulcache:
EOF
)
   actual=$(cd "$CH_IMAGE_STORAGE" && ls -1R)
   diff -u <(echo "$expected") <(echo "$actual")

   # Remove storage directory.
   rm -Rf --one-file-system "$CH_IMAGE_STORAGE"

   # Reset again; should error.
   run ch-image reset
   echo "$output"
   [[ $status -eq 1 ]]
   [[ $output = *"$CH_IMAGE_STORAGE not a builder storage"* ]]
}

@test 'ch-image storage-path' {
    run ch-image storage-path
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = /* ]]                                        # absolute path
    [[ $CH_IMAGE_STORAGE && $output = "$CH_IMAGE_STORAGE" ]]  # match what we set
}

@test 'ch-image build --bind' {
    run ch-image --no-cache build -t tmpimg -f - \
                -b "${PWD}/fixtures" -b ./fixtures:/mnt/0 . <<EOF
FROM 00_tiny
RUN mount
RUN ls -lR '${PWD}/fixtures'
RUN test -f '${PWD}/fixtures/empty-file'
RUN ls -lR /mnt/0
RUN test -f /mnt/0/empty-file
EOF
    echo "$output"
    [[ $status -eq 0 ]]
}

@test 'ch-image build: metadata carry-forward' {
    img=$CH_IMAGE_STORAGE/img/tmpimg

    # Print out current metadata, then update it.
    run ch-image build --no-cache -t tmpimg -f - . <<'EOF'
FROM charliecloud/metadata:2021-01-15
RUN echo "cwd1: $PWD"
WORKDIR /usr
RUN echo "cwd2: $PWD"
RUN env | egrep '^(PATH=|ch_)' | sed -E 's/^/env1: /' | sort
ENV ch_baz=baz-ev
RUN env | egrep '^(PATH=|ch_)' | sed -E 's/^/env2: /' | sort
RUN echo "shell1: $0"
SHELL ["/bin/sh", "-v", "-c"]
RUN echo "shell2: $0"
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'cwd1: /mnt'* ]]
    [[ $output = *'cwd2: /usr'* ]]
    [[ $output = *'env1: PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'* ]]
    [[ $output = *'env1: ch_bar=bar-ev'* ]]
    [[ $output = *'env1: ch_foo=foo-ev'* ]]
    [[ $output = *'env2: PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'* ]]
    [[ $output = *'env2: ch_bar=bar-ev'* ]]
    [[ $output = *'env2: ch_baz=baz-ev'* ]]
    [[ $output = *'env2: ch_foo=foo-ev'* ]]
    [[ $output = *'shell1: /bin/ash'* ]]
    [[ $output = *'shell2: /bin/sh'* ]]

    # Correct files?
    diff -u - <(ls "${img}/ch") <<'EOF'
config.pulled.json
environment
metadata.json
EOF

    # Volume mount points exist?
    ls -lh "${img}/mnt"
    test -d "${img}/mnt/foo"
    test -d "${img}/mnt/bar"

    # /ch/environment contents
    diff -u - "${img}/ch/environment" <<'EOF'
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ch_bar=bar-ev
ch_baz=baz-ev
ch_foo=foo-ev
EOF

    # /ch/metadata.json contents
    diff -u - "${img}/ch/metadata.json" <<'EOF'
{
  "arch": "amd64",
  "cwd": "/usr",
  "env": {
    "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    "ch_bar": "bar-ev",
    "ch_baz": "baz-ev",
    "ch_foo": "foo-ev"
  },
  "labels": {
    "ch_bar": "bar-label",
    "ch_foo": "foo-label"
  },
  "shell": [
    "/bin/sh",
    "-v",
    "-c"
  ],
  "volumes": [
    "/mnt/bar",
    "/mnt/foo"
  ]
}
EOF
}

@test 'storage directory versioning' {
   export CH_IMAGE_STORAGE="$BATS_TMPDIR"/sd-version

   # Ensure our test storage dir doesn't exist yet.
   [[ -e $CH_IMAGE_STORAGE ]] && rm -Rf --one-file-system "$CH_IMAGE_STORAGE"

   # Initialize by listing.
   run ch-image list
   echo "$output"
   [[ $status -eq 0 ]]
   [[ $output = *"initializing storage directory: v"*" ${CH_IMAGE_STORAGE}"* ]]

   # Read current version.
   v_current=$(cat "$CH_IMAGE_STORAGE"/version)

   # Version matches; success.
   run ch-image -v list
   echo "$output"
   [[ $status -eq 0 ]]
   [[ $output = *"found storage dir v${v_current}: ${CH_IMAGE_STORAGE}"* ]]

   # Fake version mismatch - non-upgradeable.
   echo '-1' > "$CH_IMAGE_STORAGE"/version
   cat "$CH_IMAGE_STORAGE"/version

   # Version mismatch; fail.
   run ch-image -v list
   echo "$output"
   [[ $status -eq 1 ]]
   [[ $output = *'error: incompatible storage directory v-1'* ]]

   # Reset.
   run ch-image reset
   echo "$output"
   [[ $status -eq 0 ]]
   [[ $output = *"initializing storage directory: v${v_current} ${CH_IMAGE_STORAGE}"* ]]

   # Version matches again; success.
   run ch-image -v list
   echo "$output"
   [[ $status -eq 0 ]]
   [[ $output = *"found storage dir v${v_current}: ${CH_IMAGE_STORAGE}"* ]]

   # Fake version mismatch - no file (v1).
   rm "$CH_IMAGE_STORAGE"/version

   # Version mismatch; upgrade; success.
   run ch-image -v list
   echo "$output"
   [[ $status -eq 0 ]]
   [[ $output = *"upgrading storage directory: v${v_current} ${CH_IMAGE_STORAGE}"* ]]
   [[ $(cat "$CH_IMAGE_STORAGE"/version) -eq "$v_current" ]]
}
