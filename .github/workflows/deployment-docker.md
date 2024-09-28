# Serverpod Deployment to a VPS using Docker

<!-- TODO(Paul): Re-do the intro and explanation, this setup is sufficient for any startup and small builds as it can scale vertically with the virtual instances until very big loads and could even be extended to scale horizontally using Hetzner's load balancers -->

This is a workflow to deploy your Serverpod to a single machine using
docker-compose. This is useful for testing and small deployments. For larger
deployments, you should use the deployment-aws.ml or deployment-gcp.yml
workflows. To reduce the workload on the machine we do not use redis in this
deployment. If you want to use redis, you need to add it to the docker-compose
file and the serverpod configuration. You need to setup the correct hostnames in
the docker-compose-production file AND the serverpod configuration file.

## Preparing the server

This guide uses the "Hetzner" Cloud, you can use any server hoster, Hetzner is just a good and cheap option.
If you want to use another architecture or hoster, check the docker-compose file and the deployment script for any necessary changes. Currently, the deployment is meant to run on ARM machines.

### Registering at Hetzner Cloud

Register an account at Hetzner Cloud and create a new project.
Using this referral link you get 20€ for free: [Hetzner Cloud](https://hetzner.cloud/?ref=BFdFFipLgfDs)

Next, go to the ["Cloud Console"](https://console.hetzner.cloud/) and create a project.

### Setting up an SSH key to connect to the server

In order to configure your server, you need to access it through ssh.
Create a SSH keypair if you don't have one yet.
If you are not sure whether you already have one, you can check by running:

```bash
cat ~/.ssh/id_rsa.pub
```

To create a new keypair, run:

Leave any options at their default values by pressing enter.

```bash
ssh-keygen -t rsa -b 4096
```

When asked for a password, just press enter.
This will create a keypair in `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`.

Copy the public key to the clipboard:

```bash
cat ~/.ssh/id_rsa.pub
```

Select the output and copy it to the clipboard.

In your Hetzner project, follow these steps:

1. Left hand-side, click on "Security" -> "SSH keys" -> "Add SSH key"
2. Add the public key you generated earlier.

### Creating a new server

Continuing in your Hetzner project, create a new server:

1. Left hand-side, go to "Server" and click "Create server"
2. In the "Image" section, click on "Apps" and select "Docker CE"
3. **Type/Architecture: Select "vCPU" and "Arm64 (Ampere)"**, the smallest tier is sufficient for most projects. You can always upgrade the specs of your server.
4. Make sure to keep the public IPv4 address.
5. SSH-Keys section, make sure your SSH-key is selected.
6. Name your server and create it.

### Setting up the server

Once the server is created, you can connect to it using SSH. Find the server ip
in the Hetzner Cloud Console and connect to it using the following command:

```bash
ssh root@<your-server-ip>
```

When prompted "Are you sure you want to continue connecting? [...]", type "yes" and press enter.

> In case you are asked for a password, the SSH key was not added correctly. You should delete the row with the ip from known_hosts (`~/.ssh/known_hosts`) and delete the server. Then create a new server and make sure to add the SSH key correctly.

For security reasons, we will create a new user to manage the deployment. This
user will not have root privileges.

#### Step 1: Create the new user

```bash
sudo adduser github-actions
```

Replace `github-actions` with your desired username. This command will prompt
you to set a password and fill in user information.

#### Step 2: Grant Docker permissions

Add the user to the `docker` group, so they can run Docker commands:

```bash
sudo usermod -aG docker github-actions
```

#### Step 3: Enable SSH access

The SSH access should be available by default for any user on the server.
However, to ensure they can access it, check the `sshd_config` file:

```bash
sudo nano /etc/ssh/sshd_config
```

Find or add the AllowUsers directive in the file. This directive specifies which
users are allowed to SSH into the server. If it doesn't exist, add it at the end
of the file. If there are multiple users, separate them with spaces:

```text
AllowUsers github-actions
```

To save and exit the file, press `Ctrl + X`, then `Y`, and finally `Enter`.
Save the file and restart the SSH service to apply changes:

```bash
sudo systemctl restart ssh
```

#### Step 4: Set up SSH key-based authentication

1. Log in as the new user:

   ```bash
   su - github-actions
   ```

2. Create a ssh keypair:

   ```bash
   ssh-keygen -t rsa -b 4096
   ```

   Leave any options at their default values by pressing enter.

3. Add your public SSH key to the `authorized_keys` file:

   ```bash
   cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
   ```

4. Restart the SSH service to apply changes:

   ```bash
   sudo systemctl restart ssh
   ```

Copy the private key to the clipboard, including the lines `-----BEGIN OPENSSH PRIVATE KEY-----` and ending with `-----END OPEN SSH PRIVATE KEY-----`. Save this key in a secure place, you will need it later.

```bash
cat ~/.ssh/id_rsa
```

## Preparing the repository

1. Create a new Personal-Access-Token (PAT) on GitHub.
   Click on your profile picture in the top right corner, go to settings, (very
   bottom) developer settings, personal access tokens, Tokens (classic), and
   click on "Generate new token".
   In the "Note" field at the top, set a name for the token, e.g., "Serverpod Deployment".
   Set the expiration time to "No expiration" and check these scopes:

   - repo (required to read repositories, especially private ones, i.e.
     accessing packages in a different repository)
   - write:packages (required to push docker images to the GitHub package registry)
     At the bottom, click on "Generate token", copy the token and save it
     somewhere safe.

2. Go to your serverpod project repository, "Settings" -> "Secrets and variables" -> "Actions"
   and create the following secrets:
   - PAT_GITHUB: Enter your GitHub PAT token here
   - PAT_USER_GITHUB: Enter your GitHub username here
   - SSH_PRIVATE_KEY: Enter the private key you generated on the server here
   - SSH_HOST: Enter the IP address of your server here
   - SSH_USER: Enter the username you created on the server here, e.g., "github-actions"

## Configuring the action

From the root of your repository, open the `.github/workflows/deployment-docker.yml` file and adjust the following settings:

- Adjust the `GHCR_ORG` variable and replace `<ORGANIZATION>` with your GitHub username, or the organization name if you got one.
-

## Server setup

on your vps / server you need to generate a keypair and add the public key to the authorized_keys file

# ssh-keygen -t rsa -b 4096

# cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

now copy the private key and add it to the secrets in the github repository

# cat ~/.ssh/id_rsa

SSH_PRIVATE_KEY: The private key for the SSH connection which you just 'cat'ed
SSH_HOST: The host for the SSH connection -> IP or domain
SSH_USER: The user for the SSH connection -> often root
