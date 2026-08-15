'use strict'

// L'agent doit démarrer avant Express afin de rattacher la transaction HTTP
// entrante à la trace propagée par apm-demo.
const apm = require('elastic-apm-node').start()
const express = require('express')

const app = express()
const port = Number(process.env.PORT || 3001)

app.get('/health', (_request, response) => {
  response.json({ status: 'ok' })
})

app.get('/work', async (_request, response, next) => {
  const span = apm.startSpan('demo.compute', 'app')

  try {
    // Une activité déterministe assez longue pour être clairement visible
    // dans le service aval de la trace distribuée.
    await new Promise((resolve) => setTimeout(resolve, 150))
    const result = Array.from({ length: 1_000 }, (_value, index) => index)
      .reduce((total, value) => total + value, 0)

    apm.setLabel('demo.endpoint', 'worker-work')
    apm.setCustomContext({ demo: { operation: 'sum-0-to-999', result } })
    response.json({ result, duration_ms: 150 })
  } catch (error) {
    next(error)
  } finally {
    span?.end()
  }
})

app.use((error, _request, response, _next) => {
  apm.captureError(error)
  response.status(500).json({ error: error.message })
})

app.listen(port, () => {
  console.log(`apm-demo-worker écoute sur le port ${port}`)
})
