#!/bin/bash
# sudo bash -c "$(curl -fsSL https://github.com/Daniel-OS01/Scripts/blob/main/docker/Docker-Cleanup-Management.sh)"
# A comprehensive Docker management script with an interactive menu.
# This script combines all the commands discussed in our conversation.

# --- Function Definitions ---

# Function to show a clear header for each section
show_header() {
    echo "================================================="
    echo "  $1"
    echo "================================================="
}

# 1) Show Docker container status
show_status() {
    show_header "Docker Container Status"
    echo "--- All Containers (Running & Stopped) ---"
    sudo docker ps -a
    echo -e "\n--- Live Resource Usage Stats (Press Ctrl+C to exit) ---"
    sudo docker stats
}

# 2) Check logs for a specific container
check_logs() {
    show_header "Check Container Logs"
    read -p "Enter the container name (e.g., dokploy-traefik): " container_name
    if [ -z "$container_name" ]; then
        echo "Error: Container name cannot be empty."
        return
    fi
    echo "--- Displaying last 100 lines for '$container_name' ---"
    sudo docker logs --tail 100 "$container_name"
}

# 3) Start a specific container
start_container() {
    show_header "Start a Container"
    read -p "Enter the container name to start: " container_name
    if [ -z "$container_name" ]; then
        echo "Error: Container name cannot be empty."
        return
    fi
    echo "Attempting to start '$container_name'..."
    sudo docker start "$container_name"
    sleep 2
    echo "--- Current status: ---"
    sudo docker ps | grep "$container_name"
}

# 4) Stop all running containers
stop_all_containers() {
    show_header "Stop All Running Containers"
    if [ -z "$(sudo docker ps -q)" ]; then
        echo "No running containers found."
    else
        read -p "Are you sure you want to stop all running containers? [y/N]: " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            echo "Stopping all containers..."
            sudo docker stop $(sudo docker ps -q)
            echo "All running containers have been stopped."
        else
            echo "Operation cancelled."
        fi
    fi
}

# 5) Remove Dokploy components
remove_dokploy() {
    show_header "Remove Dokploy Components"
    read -p "WARNING: This will remove Dokploy services, volumes, network, and files. Continue? [y/N]: " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        echo "Removing Dokploy Swarm services..."
        sudo docker service rm dokploy dokploy-traefik dokploy-postgres dokploy-redis 2>/dev/null || true
        echo "Removing Dokploy volumes..."
        sudo docker volume rm -f dokploy-postgres-database redis-data-volume 2>/dev/null || true
        echo "Removing Dokploy network..."
        sudo docker network rm -f dokploy-network 2>/dev/null || true
        echo "Removing Dokploy files from /etc/dokploy..."
        sudo rm -rf /etc/dokploy
        echo "Dokploy components removed."
    else
        echo "Operation cancelled."
    fi
}

# 6) Remove Traefik Proxy components
remove_traefik() {
    show_header "Remove Traefik Proxy Components"
    read -p "WARNING: This will remove Traefik containers, images, volumes, network, and files. Continue? [y/N]: " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        echo "Removing Traefik containers..."
        sudo docker rm -f $(sudo docker ps -aq --filter "name=traefik") 2>/dev/null || true
        echo "Removing Traefik networks..."
        sudo docker network rm -f traefik traefik-network traefik_default 2>/dev/null || true
        echo "Removing Traefik volumes..."
        sudo docker volume rm -f traefik-data traefik-config traefik-acme traefik-certificates 2>/dev/null || true
        echo "Removing Traefik configuration files..."
        sudo rm -rf /etc/traefik /opt/traefik /var/lib/traefik ~/.config/traefik
        echo "Traefik components removed."
    else
        echo "Operation cancelled."
    fi
}

# 7) Remove Nginx Proxy Manager (NPM) components
remove_npm() {
    show_header "Remove Nginx Proxy Manager (NPM) Components"
    read -p "WARNING: This will remove NPM containers, images, volumes, network, and files. Continue? [y/N]: " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        echo "Removing NPM containers..."
        sudo docker rm -f $(sudo docker ps -aq --filter "name=nginx-proxy-manager") 2>/dev/null || true
        sudo docker rm -f $(sudo docker ps -aq --filter "name=npm") 2>/dev/null || true
        echo "Removing NPM networks..."
        sudo docker network rm -f nginx-proxy-manager npm-network npm_default 2>/dev/null || true
        echo "Removing NPM volumes..."
        sudo docker volume rm -f npm-data npm-ssl npm-database nginx-proxy-manager-data nginx-proxy-manager-ssl 2>/dev/null || true
        echo "Removing NPM configuration files..."
        sudo rm -rf /etc/nginx-proxy-manager /opt/nginx-proxy-manager /var/lib/nginx-proxy-manager ~/.config/nginx-proxy-manager
        echo "NPM components removed."
    else
        echo "Operation cancelled."
    fi
}


# 8) !! DANGEROUS !! Complete Docker System Wipe
complete_wipe() {
    show_header "COMPLETE DOCKER SYSTEM WIPE"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!! WARNING !!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "This will PERMANENTLY DELETE ALL Docker containers, images, volumes,"
    echo "networks, and build cache. It will also try to remove configs for"
    echo "Dokploy, CasaOS, Coolify, Traefik, and NPM."
    echo "This action is IRREVERSIBLE."
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    read -p "Type 'YES' to confirm you want to wipe everything: " confirm
    if [ "$confirm" == "YES" ]; then
        echo "Proceeding with complete system wipe..."
        
        # Stop all containers
        if [ "$(sudo docker ps -q)" ]; then sudo docker stop $(sudo docker ps -q); fi
        
        # Remove all containers
        if [ "$(sudo docker ps -aq)" ]; then sudo docker rm -f $(sudo docker ps -aq); fi
        
        # Leave Swarm mode if active to release networks
        if sudo docker info 2>/dev/null | grep -q 'Swarm: active'; then
            if [ "$(sudo docker service ls -q 2>/dev/null)" ]; then
                sudo docker service rm $(sudo docker service ls -q) 2>/dev/null || true
            fi
            sudo docker swarm leave --force 2>/dev/null || true
        fi
        
        # The final, comprehensive cleanup command
        sudo docker system prune -a --volumes -f 2>/dev/null || true
        
        # Remove specific known networks and volumes that might persist
        sudo docker volume rm -f dokploy-postgres-database redis-data-volume traefik-data traefik-config traefik-acme traefik-certificates npm-data npm-ssl npm-database nginx-proxy-manager-data nginx-proxy-manager-ssl 2>/dev/null || true
        sudo docker network rm -f dokploy-network coolify casaos casaos-network traefik traefik-network traefik_default nginx-proxy-manager npm-network npm_default 2>/dev/null || true
        
        # Remove configuration directories
        sudo rm -rf /etc/dokploy /etc/traefik /opt/traefik /var/lib/traefik ~/.config/traefik /etc/nginx-proxy-manager /opt/nginx-proxy-manager /var/lib/nginx-proxy-manager ~/.config/nginx-proxy-manager 2>/dev/null || true
        
        echo "Docker system wipe completed."
    else
        echo "Operation cancelled. No changes were made."
    fi
}


# --- Main Menu Loop ---
while true; do
    clear
    echo "=========================================="
    echo "      Docker Management Script"
    echo "=========================================="
    echo
    echo "--- Status & Monitoring ---"
    echo "  1) Show Docker Container Status"
    echo "  2) Check Logs for a Specific Container"
    echo
    echo "--- Basic Actions ---"
    echo "  3) Start a Specific Container"
    echo "  4) Stop All Running Containers"
    echo
    echo "--- Targeted Removals (Destructive) ---"
    echo "  5) Remove Dokploy Components"
    echo "  6) Remove Traefik Proxy Components"
    echo "  7) Remove Nginx Proxy Manager (NPM) Components"
    echo
    echo "--- FULL SYSTEM WIPE (EXTREMELY DESTRUCTIVE) ---"
    echo "  8) WIPE EVERYTHING (Containers, Images, Volumes, Networks, etc.)"
    echo
    echo "  0) Exit"
    echo
    read -p "Enter your choice [0-8]: " choice

    case $choice in
        1) show_status ;;
        2) check_logs ;;
        3) start_container ;;
        4) stop_all_containers ;;
        5) remove_dokploy ;;
        6) remove_traefik ;;
        7) remove_npm ;;
        8) complete_wipe ;;
        0) echo "Exiting script."; exit 0 ;;
        *) echo "Invalid option. Please try again." ;;
    esac

    echo
    read -p "Press [Enter] to return to the menu..."
done
