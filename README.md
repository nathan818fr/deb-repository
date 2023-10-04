# nathan818's Debian Repository

This git repository contains scripts to maintain my personal Debian repository.

My personal Debian repository contains some packages that I use and that are not
available (or not up-to-date) in the official Debian repositories.

The compatibility of the provided packages is only tested on Debian stable. It
may work on other Debian-based distributions, but I can't guarantee it.

**I don't provide support. I don't add software on request.**

## Usage

To use this Debian repository, run the following commands:

```sh
wget -qO - https://deb-repo.nathan818.fr/public_key.asc | gpg --dearmor | sudo tee /usr/share/keyrings/nathan818fr-archive-keyring.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/nathan818fr-archive-keyring.gpg] https://deb-repo.nathan818.fr stable main" | sudo tee /etc/apt/sources.list.d/nathan818fr.list
sudo apt update
```

Then, you can install the software you want with:

```sh
sudo apt install <package>
```

The packages provided by this repository are listed
[here](https://github.com/nathan818fr/deb-repository/tree/site/pool/stable/main).
