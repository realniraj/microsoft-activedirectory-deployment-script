# Automated Deployment of Fault-Tolerant Active Directory in Azure

This project provides multiple Infrastructure as Code (IaC) solutions to fully automate the deployment of a highly available, two-node Microsoft Active Directory (AD) environment in Microsoft Azure. The goal is to offer a consistent, reliable, and repeatable way to provision this foundational architecture using the most popular automation tools.

Whether you prefer native PowerShell scripting, the declarative syntax of HashiCorp Terraform, or Azure's own ARM/Bicep templates, you'll find a complete, ready-to-use solution here.

---

## Deployed Architecture

Each implementation in this repository will provision the same core architecture, ensuring a consistent end-state regardless of the tool you choose.

Azure Cloud+-----------------------------------------------------------------+|                                                                 ||   Resource Group: [Your-RG-Name]                                ||   +-----------------------------------------------------------+ ||   |                                                           | ||   |   Virtual Network: [Your-VNet-Name] (10.0.0.0/16)         | ||   |   DNS Servers: 10.0.1.4, 10.0.2.4                         | ||   |   +-----------------------+ +-------------------------+   | ||   |   | Subnet 1 (10.0.1.0/24)| | Subnet 2 (10.0.2.0/24)  |   | ||   |   |                       | |                         |   | ||   |   |   [ VM: ad-dc1 ]      | |   [ VM: ad-dc2 ]        |   | ||   |   |   Private IP:         | |   Private IP:           |   | ||   |   |   10.0.1.4            | |   10.0.2.4              |   | ||   |   |   (Primary DC)        | |   (Secondary DC)        |   | ||   |   +-----------------------+ +-------------------------+   | ||   |                                                           | ||   +-----------------------------------------------------------+ ||                                                                 |+-----------------------------------------------------------------+
---

## Available Implementations

This repository is organized by tool. Please navigate to the folder for your preferred implementation to find detailed instructions and the necessary code.

* `PS/` - **PowerShell**: A comprehensive PowerShell script that uses the Az module to deploy and configure the entire environment. Ideal for those who prefer imperative scripting and are heavily invested in the PowerShell ecosystem.
* `TF/` - **Terraform**: A set of declarative Terraform configuration files to define and provision the infrastructure. Perfect for multi-cloud environments or teams that have standardized on HashiCorp's tooling.
* `ARM/` - **ARM & Bicep Templates**: (Coming Soon) Azure's native Infrastructure as Code solution. This will include both the JSON ARM templates and the cleaner Bicep DSL files.

---

## General Prerequisites

Before you begin, please ensure you have the following, regardless of the tool you choose:

1.  **Azure Subscription**: An active Azure account with permissions to create resource groups, virtual networks, virtual machines, and related resources.
2.  **Appropriate CLI/Tooling**: The necessary command-line tools for your chosen implementation (e.g., Azure PowerShell, Azure CLI, Terraform).

Specific prerequisites for each tool are detailed in the `README.md` file within its respective folder.

---

## How to Use

1.  Clone this repository to your local machine.
2.  Choose your preferred implementation method (`PS`, `TF`, or `ARM`).
3.  Navigate into the corresponding directory.
4.  Follow the detailed instructions in that directory's `README.md` file to deploy the environment.

---

## Contributing

Contributions are welcome! If you'd like to improve an existing implementation or add a new one (e.g., using Pulumi or Ansible), please feel free to fork the repository and submit a pull request.

---

## License

This project is licensed under the **MIT License**. See the `LICENSE` file for full details.
