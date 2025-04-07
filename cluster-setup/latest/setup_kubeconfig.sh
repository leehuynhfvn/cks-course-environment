#!/bin/bash
#
# Script cấu hình kubectl config cho cụm Kubernetes
# Tạo ngày: 7/4/2025
#

set -e

# Màu sắc để hiển thị
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Đang thiết lập cấu hình kubectl...${NC}"

# Kiểm tra xem có đang chạy dưới quyền root hay không
if [[ $EUID -eq 0 ]]; then
  echo -e "${YELLOW}Bạn đang chạy script với quyền root.${NC}"
  
  # Kiểm tra xem người dùng muốn thiết lập cho tài khoản root hay cho người dùng thông thường
  read -p "Bạn muốn cấu hình kubectl cho tài khoản root (r) hay cho một người dùng khác (u)? [r/u]: " user_choice
  
  if [[ "$user_choice" == "u" || "$user_choice" == "U" ]]; then
    read -p "Nhập tên người dùng cần cấu hình: " username
    
    # Kiểm tra xem người dùng có tồn tại không
    if id "$username" &>/dev/null; then
      echo -e "${GREEN}Đang cấu hình kubectl cho người dùng $username...${NC}"
      sudo -u $username mkdir -p /home/$username/.kube
      sudo cp -i /etc/kubernetes/admin.conf /home/$username/.kube/config
      sudo chown $(id -u $username):$(id -g $username) /home/$username/.kube/config
      echo -e "${GREEN}Đã cấu hình kubectl thành công cho người dùng $username!${NC}"
    else
      echo -e "${RED}Người dùng $username không tồn tại!${NC}"
      exit 1
    fi
  else
    echo -e "${GREEN}Đang cấu hình kubectl cho tài khoản root...${NC}"
    export KUBECONFIG=/etc/kubernetes/admin.conf
    
    # Thêm vào bashrc của root
    if ! grep -q "export KUBECONFIG=/etc/kubernetes/admin.conf" /root/.bashrc; then
      echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> /root/.bashrc
      echo -e "${GREEN}Đã thêm KUBECONFIG vào .bashrc của root${NC}"
    fi
    
    echo -e "${GREEN}Đã cấu hình kubectl thành công cho tài khoản root!${NC}"
  fi
else
  # Đang chạy với quyền của người dùng thông thường
  echo -e "${GREEN}Đang cấu hình kubectl cho tài khoản hiện tại...${NC}"
  
  # Tạo thư mục .kube nếu chưa có
  mkdir -p $HOME/.kube
  
  # Kiểm tra nếu người dùng có quyền sudo
  if command -v sudo &> /dev/null; then
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    echo -e "${GREEN}Đã cấu hình kubectl thành công!${NC}"
  else
    echo -e "${RED}Lỗi: Bạn cần có quyền sudo để sao chép file admin.conf!${NC}"
    echo -e "${YELLOW}Vui lòng chạy script này với quyền sudo hoặc root.${NC}"
    exit 1
  fi
fi

# Kiểm tra kết nối tới cluster
echo -e "${YELLOW}Kiểm tra kết nối đến cụm Kubernetes...${NC}"
if kubectl cluster-info &>/dev/null; then
  echo -e "${GREEN}Kết nối đến cụm Kubernetes thành công!${NC}"
  echo -e "${YELLOW}Thông tin cụm:${NC}"
  kubectl cluster-info
  
  echo -e "\n${YELLOW}Danh sách các node:${NC}"
  kubectl get nodes
else
  echo -e "${RED}Không thể kết nối đến cụm Kubernetes. Vui lòng kiểm tra lại cài đặt.${NC}"
fi

echo -e "\n${GREEN}Thiết lập hoàn tất!${NC}"