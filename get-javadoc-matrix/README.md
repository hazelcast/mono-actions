### setup-maven Action

A GitHub Action to get JavaDoc matrix for job concurrency

#### Inputs

| Name         | Required | Description                |
|:-------------|:---------|:---------------------------|
| release-type | No       | Release Edition ALL|OSS|EE |

#### Outputs

| Name | Description                   |
|:-----|:------------------------------|
| json | Matrix JSon anchored by label |

## Usage

Example workflow:

```yaml
jobs:
  test-mono:
    runs-on: ubuntu-latest
    steps:
      - uses: hazelcast/mono-actions/get-javadox-matrix@main
        id: get-javadox-matrix
      - run: echo "Matrix JSON: ${{ steps.get-javadox-matrix.outputs.json }}"
```
