# Portable Development Scripts

## Overview

This repository contains a collection of **portable scripts** designed to simplify and standardize software development workflows.

It is primarily intended to be used as a **Git submodule** inside other projects, providing a shared and consistent toolkit across multiple codebases.

The main focus is on **C and C++ development using CMake on Ubuntu-based systems**, but many scripts are written to remain adaptable across environments.

These tools aim to:

* Reduce repetitive setup tasks
* Provide consistent build and development workflows across projects
* Enable reuse through submodule integration
* Improve productivity in local and portable environments

---

## Features

* ⚙️ **C/C++ Build Automation** using CMake
* 📦 **Environment Setup Scripts** for Ubuntu
* 🔁 **Reusable Utilities** for common development tasks
* 🧰 **Portable by Design** (minimal dependencies where possible)

---

## Usage

### As a Git Submodule (Recommended)

Add this repository as a submodule to your project:

```bash
git submodule add https://github.com/sauronc0de/scripts ${WORKSPACE_DIR}
```

Initialize and update submodules:

```bash
git submodule update --init --recursive
```
### First steps

To get an overview of the available scripts and their purpose, run:

```sh
./scripts/help.sh
```

### Expected environment variables

The following variables are commonly expected:
* `WORKSPACE_DIR`: Root directory where the project is mounted or developed
* `PROJECT_NAME`: Name of the project
* `USERNAME`: Default user inside the environment/container

---

## Philosophy

* **Simplicity over complexity** — scripts should be easy to read and modify
* **Portability first** — avoid unnecessary dependencies
* **Developer-focused** — optimize for real-world workflows
* **Consistency enforced** — all scripts must follow the repository [guidelines](docs/scripts_guidelines.md)