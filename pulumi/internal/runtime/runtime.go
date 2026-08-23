package runtime

import (
	"strings"

	"github.com/huynhtt8/homelab/pulumi/internal/config"
	"github.com/huynhtt8/homelab/pulumi/internal/naming"
	corev1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/core/v1"
	metav1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/meta/v1"
	networkingv1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/networking/v1"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

const mediaClaimName = "media-share"
const traefikNamespace = "traefik"

func ensureNamespace(ctx *pulumi.Context, ns string) (*corev1.Namespace, error) {
	existing, err := corev1.GetNamespace(ctx, naming.Resource("namespace", ns), pulumi.ID(ns), nil)
	if err == nil {
		return existing, nil
	}

	if !strings.Contains(err.Error(), "not found") && !strings.Contains(err.Error(), "does not exist") {
		return nil, err
	}

	return corev1.NewNamespace(ctx, naming.Resource("namespace", ns), &corev1.NamespaceArgs{
		Metadata: &metav1.ObjectMetaArgs{
			Name: pulumi.String(ns),
			Labels: pulumi.StringMap{
				"app.kubernetes.io/managed-by": pulumi.String("pulumi"),
			},
		},
	})
}

func Create(ctx *pulumi.Context, cfg config.RuntimeConfig) error {
	namespaces := map[string]*corev1.Namespace{}
	for _, namespace := range cfg.TargetNamespaces() {
		ns, err := ensureNamespace(ctx, namespace)
		if err != nil {
			return err
		}
		namespaces[namespace] = ns
	}

	for _, namespace := range cfg.TargetNamespaces() {
		pvName := namespace + "-" + mediaClaimName
		_, err := corev1.NewPersistentVolume(ctx, naming.Resource("pv", pvName), &corev1.PersistentVolumeArgs{
			Metadata: &metav1.ObjectMetaArgs{
				Name: pulumi.String(pvName),
				Labels: pulumi.StringMap{
					"app.kubernetes.io/managed-by": pulumi.String("pulumi"),
					"app.kubernetes.io/part-of":    pulumi.String("homelab"),
				},
			},
			Spec: &corev1.PersistentVolumeSpecArgs{
				AccessModes: pulumi.StringArray{
					pulumi.String("ReadWriteMany"),
				},
				Capacity: pulumi.StringMap{
					"storage": pulumi.String("1Gi"),
				},
				MountOptions: pulumi.StringArray{
					pulumi.String("nfsvers=4.1"),
					pulumi.String("timeo=30"),
					pulumi.String("retrans=3"),
				},
				Nfs: &corev1.NFSVolumeSourceArgs{
					Server: pulumi.String(cfg.NFSServer),
					Path:   pulumi.String(cfg.TargetMediaPath()),
				},
				PersistentVolumeReclaimPolicy: pulumi.String("Retain"),
				StorageClassName:              pulumi.String(""),
			},
		})
		if err != nil {
			return err
		}

		_, err = corev1.NewPersistentVolumeClaim(ctx, naming.Resource("pvc", namespace+"-"+mediaClaimName), &corev1.PersistentVolumeClaimArgs{
			Metadata: &metav1.ObjectMetaArgs{
				Name:      pulumi.String(mediaClaimName),
				Namespace: pulumi.String(namespace),
				Labels: pulumi.StringMap{
					"app.kubernetes.io/managed-by": pulumi.String("pulumi"),
					"app.kubernetes.io/part-of":    pulumi.String("homelab"),
				},
			},
			Spec: &corev1.PersistentVolumeClaimSpecArgs{
				AccessModes: pulumi.StringArray{
					pulumi.String("ReadWriteMany"),
				},
				Resources: &corev1.VolumeResourceRequirementsArgs{
					Requests: pulumi.StringMap{
						"storage": pulumi.String("1Gi"),
					},
				},
				StorageClassName: pulumi.String(""),
				VolumeName:       pulumi.String(pvName),
			},
		}, pulumi.DependsOn([]pulumi.Resource{namespaces[namespace]}))
		if err != nil {
			return err
		}
	}

	if err := createAdGuardHomeIngress(ctx, cfg); err != nil {
		return err
	}

	ctx.Export("mediaShareCount", pulumi.Int(len(cfg.TargetNamespaces())))
	return nil
}

func createAdGuardHomeIngress(ctx *pulumi.Context, cfg config.RuntimeConfig) error {
	host := strings.TrimSpace(cfg.AdGuardHomeHost)
	if host == "" {
		return nil
	}

	namespace, err := ensureNamespace(ctx, traefikNamespace)
	if err != nil {
		return err
	}

	_, err = corev1.NewService(ctx, naming.Resource("service", "adguard-home"), &corev1.ServiceArgs{
		Metadata: &metav1.ObjectMetaArgs{
			Name:      pulumi.String("adguard-home"),
			Namespace: pulumi.String(traefikNamespace),
			Labels: pulumi.StringMap{
				"app.kubernetes.io/managed-by": pulumi.String("pulumi"),
				"app.kubernetes.io/part-of":    pulumi.String("homelab"),
			},
		},
		Spec: &corev1.ServiceSpecArgs{
			Type:         pulumi.String("ExternalName"),
			ExternalName: pulumi.String(host),
			Ports: corev1.ServicePortArray{
				&corev1.ServicePortArgs{
					Name:       pulumi.String("http"),
					Port:       pulumi.Int(82),
					TargetPort: pulumi.Int(82),
					Protocol:   pulumi.String("TCP"),
				},
			},
		},
	}, pulumi.DependsOn([]pulumi.Resource{namespace}))
	if err != nil {
		return err
	}

	_, err = networkingv1.NewIngress(ctx, naming.Resource("ingress", "adguard-home"), &networkingv1.IngressArgs{
		Metadata: &metav1.ObjectMetaArgs{
			Name:      pulumi.String("adguard-home"),
			Namespace: pulumi.String(traefikNamespace),
			Labels: pulumi.StringMap{
				"app.kubernetes.io/managed-by": pulumi.String("pulumi"),
				"app.kubernetes.io/part-of":    pulumi.String("homelab"),
			},
			Annotations: pulumi.StringMap{
				"cert-manager.io/cluster-issuer": pulumi.String("homelab-ca"),
			},
		},
		Spec: &networkingv1.IngressSpecArgs{
			IngressClassName: pulumi.String("traefik"),
			Tls: networkingv1.IngressTLSArray{
				&networkingv1.IngressTLSArgs{
					Hosts: pulumi.StringArray{
						pulumi.String("adguard.homelab.com"),
					},
					SecretName: pulumi.String("adguard-home-tls"),
				},
			},
			Rules: networkingv1.IngressRuleArray{
				&networkingv1.IngressRuleArgs{
					Host: pulumi.String("adguard.homelab.com"),
					Http: &networkingv1.HTTPIngressRuleValueArgs{
						Paths: networkingv1.HTTPIngressPathArray{
							&networkingv1.HTTPIngressPathArgs{
								Path:     pulumi.String("/"),
								PathType: pulumi.String("Prefix"),
								Backend: &networkingv1.IngressBackendArgs{
									Service: &networkingv1.IngressServiceBackendArgs{
										Name: pulumi.String("adguard-home"),
										Port: &networkingv1.ServiceBackendPortArgs{
											Name: pulumi.String("http"),
										},
									},
								},
							},
						},
					},
				},
			},
		},
	}, pulumi.DependsOn([]pulumi.Resource{namespace}))
	return err
}
