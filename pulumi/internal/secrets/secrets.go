package secrets

import (
	"strings"

	"github.com/huynhtt8/homelab/pulumi/internal/config"
	"github.com/huynhtt8/homelab/pulumi/internal/naming"
	corev1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/core/v1"
	metav1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/meta/v1"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func ensureNamespace(ctx *pulumi.Context, ns string) (*corev1.Namespace, error) {
	existing, err := corev1.GetNamespace(ctx, naming.Resource("namespace", ns), pulumi.ID(ns), nil)
	if err == nil {
		return existing, nil
	}

	if !strings.Contains(err.Error(), "not found") {
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

func Create(ctx *pulumi.Context, secrets []config.Secret) error {
	// Collect unique namespaces and ensure they exist
	namespaces := map[string]*corev1.Namespace{}
	for _, secret := range secrets {
		ns := secret.TargetNamespace()
		if _, exists := namespaces[ns]; !exists {
			namespace, err := ensureNamespace(ctx, ns)
			if err != nil {
				return err
			}
			namespaces[ns] = namespace
		}
	}

	for _, secret := range secrets {
		stringData := pulumi.StringMap{}
		for key, value := range secret.Data {
			stringData[key] = pulumi.String(value)
		}

		namespace := secret.TargetNamespace()
		_, err := corev1.NewSecret(ctx, naming.Resource("secret", namespace+"-"+secret.Name), &corev1.SecretArgs{
			Metadata: &metav1.ObjectMetaArgs{
				Name:      pulumi.String(secret.Name),
				Namespace: pulumi.String(namespace),
				Labels: pulumi.StringMap{
					"app.kubernetes.io/managed-by": pulumi.String("pulumi"),
					"app.kubernetes.io/part-of":    pulumi.String("homelab"),
				},
			},
			StringData: stringData,
			Type:       pulumi.String("Opaque"),
		}, pulumi.DependsOn([]pulumi.Resource{namespaces[namespace]}))
		if err != nil {
			return err
		}
	}

	ctx.Export("secretCount", pulumi.Int(len(secrets)))
	return nil
}
