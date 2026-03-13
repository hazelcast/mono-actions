### setup-maven Action

A GitHub Action to setup Maven:
- JDK
- Maven common args
- Maven cache

#### Inputs

| Name      | Required | Description                                              |
|:----------|:---------|:---------------------------------------------------------|
| mono-root | No       | Custom Mono root folder. Defaults to ${GITHUB_WORKSPACE} |
| gh-token  | Yes      | Token used to fetch files                                |

#### Outputs

| Name             | Description                            |
|:-----------------|:---------------------------------------|
| cache-hit        | If there was cache hit                 |
| cache-key        | The key to the cachje                  |
| local-repository | Path to Maven local repository (~/.m2) |

## Usage

Example workflow:

```yaml
jobs:
  test-mono:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hazelcast/mono-actions/setup-maven@main
        id: setup-maven
      - run: echo "Maven local repo: ${{ steps.setup-maven.outputs.local-repository }}"

  test-mono-custom:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Mono
        uses: actions/checkout@v6
        with:
          repository: hazelcast/hazelcast-mono
          path: hazelcast-mono

      - name: Run setup-maven composite action
        id: setup-maven
        uses: ./setup-maven
        with:
          mono-root: ${{ github.workspace }}/hazelcast-mono
      - run: echo "Maven local repo: ${{ steps.setup-maven.outputs.local-repository }}"
```
