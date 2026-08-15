'use strict'

// L'agent doit démarrer avant Express afin d'instrumenter les requêtes HTTP.
const apm = require('elastic-apm-node').start()
const http = require('node:http')
const express = require('express')

const app = express()
const port = Number(process.env.PORT || 3000)
const workerUrl = new URL(process.env.WORKER_URL || 'http://localhost:3001/work')

function requestWorker() {
  return new Promise((resolve, reject) => {
    // Le module http est instrumenté par elastic-apm-node. L'agent injecte le
    // contexte W3C traceparent : la transaction du worker rejoint donc celle
    // initiée par la requête reçue par ce service.
    const request = http.get(workerUrl, { timeout: 2_000 }, (workerResponse) => {
      let body = ''

      workerResponse.setEncoding('utf8')
      workerResponse.on('data', (chunk) => {
        body += chunk
      })
      workerResponse.on('end', () => {
        if (workerResponse.statusCode !== 200) {
          reject(new Error(`Le worker a répondu ${workerResponse.statusCode}: ${body}`))
          return
        }

        try {
          resolve(JSON.parse(body))
        } catch (error) {
          reject(new Error(`Réponse JSON invalide du worker: ${error.message}`))
        }
      })
    })

    request.on('timeout', () => {
      request.destroy(new Error('Le worker a dépassé le délai de 2 secondes'))
    })
    request.on('error', reject)
  })
}

app.get('/health', (_request, response) => {
  response.json({ status: 'ok' })
})

app.get('/', (_request, response) => {
  response.json({
    message: 'APM demo prête',
    endpoints: ['/work', '/error', '/health'],
    worker_url: workerUrl.toString()
  })
})

app.get('/work', async (_request, response, next) => {
  const span = apm.startSpan('demo.delegate-to-worker', 'app')

  try {
    apm.setLabel('demo.endpoint', 'work')
    const work = await requestWorker()
    apm.setCustomContext({ demo: { operation: 'delegated-work', worker: 'apm-demo-worker', result: work.result } })
    response.json({ ...work, worker: 'apm-demo-worker' })
  } catch (error) {
    next(error)
  } finally {
    span?.end()
  }
})

app.get('/error', (_request, _response, next) => {
  next(new Error('Erreur contrôlée générée par apm-demo'))
})

app.use((error, _request, response, _next) => {
  apm.captureError(error)
  response.status(error.message.includes('worker') ? 502 : 500).json({ error: error.message })
})

app.listen(port, () => {
  console.log(`apm-demo écoute sur le port ${port}`)
})
