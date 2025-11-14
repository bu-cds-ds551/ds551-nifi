# OpenShift-Compatible NiFi Image

This directory contains a Dockerfile to build an OpenShift-compatible version of Apache NiFi.

## Why This Custom Image?

The official Apache NiFi Docker images are **not compatible** with OpenShift's default Security Context Constraints (SCC) because:

1. They run as UID 1000 (hardcoded)
2. They require write access to `/opt/nifi/nifi-current/conf/`
3. The startup scripts use `sed -i` to modify configuration files

OpenShift assigns **arbitrary UIDs** (e.g., 1011040000+) and restricts filesystem writes. This custom image solves these issues by:

- Using **group 0 (root group)** ownership for all NiFi directories
- Setting **g+w** (group write) permissions on all necessary directories
- Allowing OpenShift to assign any UID while maintaining write access via group membership

## Building the Image

### Local Build

```bash
cd nifi/openshift-image
docker build -t nifi-openshift:1.24.0 .
```

### Build for OpenShift Internal Registry

```bash
# Login to OpenShift
oc login

# Create ImageStream
oc create imagestream nifi-openshift -n <your-namespace>

# Build and push using OpenShift
oc new-build --name=nifi-openshift \
  --dockerfile=- \
  --to=nifi-openshift:1.24.0 \
  -n <your-namespace> < Dockerfile

# Or build locally and push
docker build -t image-registry.openshift-image-registry.svc:5000/<your-namespace>/nifi-openshift:1.24.0 .
docker push image-registry.openshift-image-registry.svc:5000/<your-namespace>/nifi-openshift:1.24.0
```

### Push to External Registry (e.g., Quay.io, Docker Hub)

```bash
# Tag for your registry
docker tag nifi-openshift:1.24.0 quay.io/<your-org>/nifi-openshift:1.24.0

# Login and push
docker login quay.io
docker push quay.io/<your-org>/nifi-openshift:1.24.0
```

## Using the Image

Update `nifi/plain/nifi-statefulset.yaml` to use your custom image:

```yaml
containers:
  - name: nifi
    image: image-registry.openshift-image-registry.svc:5000/<your-namespace>/nifi-openshift:1.24.0
    # OR from external registry:
    # image: quay.io/<your-org>/nifi-openshift:1.24.0
```

Then deploy:

```bash
cd ../..  # Back to ds551-infra directory
./deploy.sh  # Choose option 2 (NiFi)
```

## Verification

After deployment, verify the pod runs successfully:

```bash
kubectl get pods -n <your-namespace> -l app=ds551-nifi
kubectl logs ds551-nifi-0 -n <your-namespace>

# Should see:
# NiFi running with PID ...
```

Check the UID it's running as:

```bash
kubectl exec ds551-nifi-0 -n <your-namespace> -- id
# Should show something like:
# uid=1011040000 gid=0(root) groups=0(root),1011040000
```

## Key Differences from Official Image

| Aspect | Official Image | OpenShift Image |
|--------|---------------|-----------------|
| User | `nifi:nifi` (1000:1000) | `nifi:root` (1000:0) |
| Directory ownership | `nifi:nifi` | `nifi:root` |
| Group permissions | Default umask | `g+w` on all writable dirs |
| UID flexibility | Fixed 1000 | Any UID (group 0 membership) |
| OpenShift SCC | Requires `anyuid` | Works with `restricted-v2` |

## Troubleshooting

### Permission Errors

If you still see permission errors:

```bash
kubectl logs ds551-nifi-0 -n <your-namespace>
# Look for "Permission denied" messages
```

Check the pod's security context:

```bash
kubectl get pod ds551-nifi-0 -n <your-namespace> -o yaml | grep -A 10 securityContext
```

Ensure:
1. `runAsUser` is NOT set (let OpenShift assign)
2. `fsGroup: 0` or let OpenShift assign

### Image Pull Errors

If using OpenShift internal registry:

```bash
# Verify ImageStream
oc get imagestream nifi-openshift -n <your-namespace>

# Check image pull secrets
oc get secrets | grep docker
```

### Build Failures

If the build fails downloading NiFi:

```bash
# Check the Apache mirror
curl -I https://archive.apache.org/dist/nifi/1.24.0/nifi-1.24.0-bin.zip

# Try alternative mirrors by modifying MIRROR_BASE_URL in Dockerfile
```

## References

- [OpenShift Creating Images](https://docs.openshift.com/container-platform/latest/openshift_images/create-images.html)
- [OpenShift SCC Guidelines](https://docs.openshift.com/container-platform/latest/authentication/managing-security-context-constraints.html)
- [Apache NiFi Dockerfile](https://github.com/apache/nifi/blob/main/nifi-docker/dockerhub/Dockerfile)
- [Red Hat Universal Base Images Best Practices](https://www.redhat.com/en/blog/introducing-red-hat-universal-base-image)
