### get-javadoc-matrix Action

A GitHub Action to generate a JavaDoc matrix for distributed jobs

#### Inputs

| Name         | Required | Description                |
|:-------------|:---------|:---------------------------|
| release-type | No       | Release Edition ALL|OSS|EE |

#### Outputs

| Name | Description                   |
|:-----|:------------------------------|
| json | Matrix JSON anchored by label |

## Usage

Example workflow:

```yaml
jobs:
  test-mono:
    runs-on: ubicloud-standard-2
    steps:
      - uses: hazelcast/mono-actions/get-javadox-matrix@main
        id: get-javadox-matrix
      - run: echo "Matrix JSON: ${{ steps.get-javadox-matrix.outputs.json }}"
```
