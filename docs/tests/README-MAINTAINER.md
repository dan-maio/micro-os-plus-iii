[![GitHub issues](https://img.shields.io/github/issues/micro-os-plus/micro-os-plus-iii-smp.svg)](https://github.com/micro-os-plus/micro-os-plus-iii-smp/issues/)
[![GitHub pulls](https://img.shields.io/github/issues-pr/micro-os-plus/micro-os-plus-iii-smp.svg)](https://github.com/micro-os-plus/micro-os-plus-iii-smp/pulls)

# Maintainer info

> **Scope.** This file is the upstream library/packaging guide, kept for
> reference. The test harness of this repository lives in
> `micro-os-plus-iii-smp.git/tests`; the current guides are
> [`STEPS.md`](STEPS.md) and [`TESTS-CATALOG.md`](TESTS-CATALOG.md).


## Project repository

The project is hosted on GitHub:

- <https://github.com/micro-os-plus/micro-os-plus-iii-smp.git>

To clone the stable branch (`xpack`), run the following commands in a
terminal (on Windows use the _Git Bash_ console):

```sh
rm -rf ~/Work/micro-os-plus-iii-smp.git && \
mkdir -p ~/Work/micro-os-plus && \
git clone \
  https://github.com/micro-os-plus/micro-os-plus-iii-smp.git \
  ~/Work/micro-os-plus-iii-smp.git
```

For development purposes, clone the `xpack-development` branch:

```sh
rm -rf ~/Work/micro-os-plus-iii-smp.git && \
mkdir -p ~/Work/micro-os-plus && \
git clone \
  --branch xpack-development \
  https://github.com/micro-os-plus/micro-os-plus-iii-smp.git \
  ~/Work/micro-os-plus-iii-smp.git
```

Or, if the repo was already cloned:

```sh
git -C ~/Work/micro-os-plus-iii-smp.git pull
```

## Prerequisites

A recent [xpm](https://xpack.github.io/xpm/), which is a portable
[Node.js](https://nodejs.org/) command line application.

## How to make new releases

### Release schedule

There are no fixed releases, the project aims to follow the upstream releases.

### Check Git

In the `micro-os-plus/micro-os-plus-iii-smp` Git repo:

- switch to the `xpack-development` branch
- if needed, merge the `xpack` branch

No need to add a tag here, it'll be added when the release is created.

### Increase the version

Update the`package.json` file; add an extra field in the
pre-release field, and initially also add `.pre`,
for example `7.1.0-pre.1`.

### Fix possible open issues

Check GitHub issues and pull requests:

- <https://github.com/micro-os-plus/micro-os-plus-iii-smp/issues/>

and fix them; assign them to a milestone (like `7.1.0`).

### Update os-version.h

Update the #define to represent the version.

### Update `README-MAINTAINER.md`

Update the following files to reflect the changes
related to the new version:

- `README-MAINTAINER.md`
- `README.md`

### Update `CHANGELOG.md`

- open the `CHANGELOG.md` file
- check if all previous fixed issues are in
- add a new entry like _* v7.1.0 prepared_
- commit with a message like _prepare v7.1.0_

### Push changes

- commit and push

### Testing

To run all available tests:

```sh
git -C ~/Work/micro-os-plus-iii-smp.git pull
xpm run deep-clean -C ~/Work/micro-os-plus-iii-smp.git/tests
xpm run install-all -C ~/Work/micro-os-plus-iii-smp.git/tests
xpm run test-all -C ~/Work/micro-os-plus-iii-smp.git/tests
```

### Commit the new version

- select the `xpack-development` branch
- commit all changes
- `npm pack` and check the content of the archive, which should list
  only `package.json`, `README.md`, `LICENSE`, `CHANGELOG.md`,
  the `doxygen-awesome-*.js` and `doxygen-custom/*` files;
  possibly adjust `.npmignore`
- `npm version 7.1.0`
- push the `xpack-development` branch to GitHub
- the `postversion` npm script should also update tags via `git push origin --tags`

The workflow result and logs are available from the
[Actions](https://github.com/micro-os-plus/micro-os-plus-iii-smp/actions) page.

### Update the repo

When the package is considered stable:

- with a Git client (VS Code is fine)
- merge `xpack-development` into `xpack`
- push to GitHub
- select `xpack-development`

## Share on Twitter

- in a separate browser windows, open [TweetDeck](https://tweetdeck.twitter.com/)
- using the `@xpack_project` account
- paste the release name like **µOS++ IIIe v7.1.0 released**
- paste the link to the Web page
  [release](https://micro-os-plus.github.io/micro-os-plus/iii/releases/)
- click the **Tweet** button
