#!/bin/bash
# Build and push OpenShift-compatible NiFi image
set -e

# Default values
NIFI_VERSION=${NIFI_VERSION:-1.24.0}
BUILD_METHOD=${BUILD_METHOD:-local}  # local, openshift, or external

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "OpenShift-Compatible NiFi Image Builder"
echo "=========================================="
echo "NiFi Version: ${NIFI_VERSION}"
echo "Build Method: ${BUILD_METHOD}"
echo ""

# Function to build locally
build_local() {
    echo "${GREEN}Building image locally...${NC}"
        if command -v podman &> /dev/null; then
            OCI=podman
        elif command -v docker &> /dev/null; then
            OCI=docker
        else
            echo "${RED}ERROR: Neither podman nor docker is installed.${NC}"
            exit 1
        fi
        $OCI build \
            --build-arg NIFI_VERSION=${NIFI_VERSION} \
            -t nifi-openshift:${NIFI_VERSION} \
            -t nifi-openshift:latest \
            .
        echo "${GREEN}✓ Build complete!${NC}"
        echo ""
        echo "Image: nifi-openshift:${NIFI_VERSION}"
        echo ""
        echo "To test locally:"
        echo "  $OCI run -p 8443:8443 \\"
        echo "    -e SINGLE_USER_CREDENTIALS_USERNAME=admin \\"
        echo "    -e SINGLE_USER_CREDENTIALS_PASSWORD=password123 \\"
        echo "    nifi-openshift:${NIFI_VERSION}"
}

# Function to build and push to OpenShift internal registry
build_openshift() {
    echo "${GREEN}Building and pushing to OpenShift internal registry...${NC}"

    # Check if logged in to OpenShift
    if ! oc whoami &> /dev/null; then
        echo "${RED}ERROR: Not logged in to OpenShift${NC}"
        echo "Run: oc login"
        exit 1
    fi

    NAMESPACE=$(oc project -q)
    echo "Current namespace: ${NAMESPACE}"

    # Create ImageStream if it doesn't exist
    if ! oc get imagestream nifi-openshift &> /dev/null; then
        echo "Creating ImageStream..."
        oc create imagestream nifi-openshift
    fi

    # Start build
    echo "Starting OpenShift build..."
    oc new-build --name=nifi-openshift \
        --dockerfile=- \
        --to=nifi-openshift:${NIFI_VERSION} \
        < Dockerfile || \
    oc start-build nifi-openshift --from-dir=. --follow

    echo "${GREEN}✓ Build and push complete!${NC}"
    echo ""
    echo "Image: image-registry.openshift-image-registry.svc:5000/${NAMESPACE}/nifi-openshift:${NIFI_VERSION}"
    echo ""
    echo "Update your StatefulSet to use:"
    echo "  image: image-registry.openshift-image-registry.svc:5000/${NAMESPACE}/nifi-openshift:${NIFI_VERSION}"
}

# Function to build and push to external registry
build_external() {
    echo "${GREEN}Building for external registry...${NC}"

    # Prompt for registry details
    read -p "Enter registry URL (e.g., quay.io, docker.io): " REGISTRY
    read -p "Enter organization/username: " ORG

    FULL_IMAGE="${REGISTRY}/${ORG}/nifi-openshift:${NIFI_VERSION}"

    echo "Building image..."
        if command -v podman &> /dev/null; then
            OCI=podman
        elif command -v docker &> /dev/null; then
            OCI=docker
        else
            echo "${RED}ERROR: Neither podman nor docker is installed.${NC}"
            exit 1
        fi
        $OCI build \
            --build-arg NIFI_VERSION=${NIFI_VERSION} \
            -t ${FULL_IMAGE} \
            -t ${REGISTRY}/${ORG}/nifi-openshift:latest \
            .

    echo "${YELLOW}Ready to push to ${FULL_IMAGE}${NC}"
    read -p "Push now? (y/n): " PUSH

    if [ "$PUSH" = "y" ] || [ "$PUSH" = "Y" ]; then
        echo "Logging in to ${REGISTRY}..."
        $OCI login ${REGISTRY}

        echo "Pushing image..."
        $OCI push ${FULL_IMAGE}
        $OCI push ${REGISTRY}/${ORG}/nifi-openshift:latest

        echo "${GREEN}✓ Push complete!${NC}"
        echo ""
        echo "Image: ${FULL_IMAGE}"
        echo ""
        echo "Update your StatefulSet to use:"
        echo "  image: ${FULL_IMAGE}"
    fi
}

# Main execution
case ${BUILD_METHOD} in
    local)
        build_local
        ;;
    openshift)
        build_openshift
        ;;
    external)
        build_external
        ;;
    *)
        echo "${RED}ERROR: Unknown build method: ${BUILD_METHOD}${NC}"
        echo "Valid options: local, openshift, external"
        echo ""
        echo "Usage:"
        echo "  BUILD_METHOD=local ./build-image.sh"
        echo "  BUILD_METHOD=openshift ./build-image.sh"
        echo "  BUILD_METHOD=external ./build-image.sh"
        exit 1
        ;;
esac

echo ""
echo "${GREEN}=========================================="
echo "Build process complete!"
echo "==========================================${NC}"
